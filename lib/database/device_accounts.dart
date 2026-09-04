import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';

/// Somebody who has signed in on this device.
///
/// This is a local convenience, not a credential. It holds no token and no
/// secret: signing in still takes a passkey, a password or Google, and every
/// rule in firestore.rules is evaluated against the account that actually
/// authenticated. Deleting the app takes all of it with them.
@immutable
class DeviceAccount {
  const DeviceAccount({
    required this.uid,
    required this.displayName,
    required this.email,
    this.passkeyIds = const [],
    this.lastSignedIn,
  });

  final String uid;
  final String displayName;
  final String email;

  /// Credential ids of passkeys registered on *this* device for this person.
  ///
  /// Kept locally rather than asked for, because asking a server "which
  /// passkeys belong to this account" from a signed-out screen is an
  /// enumeration oracle. Here they are only ever written by the person who
  /// just used them, so the device knows what it has seen and nothing more.
  final List<String> passkeyIds;

  final DateTime? lastSignedIn;

  /// What the picker calls this person. An entry can exist for a moment with
  /// neither — a passkey sign-in records the credential before the session has
  /// resolved a name — and a blank tile is unusable, so it says so.
  String get label => displayName.trim().isNotEmpty
      ? displayName.trim()
      : (email.trim().isNotEmpty ? email.trim() : 'This account');

  /// Initials for the picker's avatars, on the same rule as [AppUser.initials]
  /// so a person looks the same on both sides of signing in.
  String get initials => AppUser(
        uid: uid,
        email: email,
        displayName: displayName,
        storeId: '',
      ).initials;

  DeviceAccount copyWith({
    String? displayName,
    String? email,
    List<String>? passkeyIds,
    DateTime? lastSignedIn,
  }) =>
      DeviceAccount(
        uid: uid,
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        passkeyIds: passkeyIds ?? this.passkeyIds,
        lastSignedIn: lastSignedIn ?? this.lastSignedIn,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'email': email,
        'passkeyIds': passkeyIds,
        'lastSignedIn': lastSignedIn?.toIso8601String(),
      };

  factory DeviceAccount.fromJson(Map<String, dynamic> json) => DeviceAccount(
        uid: json['uid'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        passkeyIds: (json['passkeyIds'] as List<Object?>? ?? const [])
            .whereType<String>()
            .toList(),
        lastSignedIn: DateTime.tryParse(json['lastSignedIn'] as String? ?? ''),
      );
}

/// The roster the entry screen is built on: who uses this till.
///
/// The problem it exists for is not authentication, which already works. It is
/// that on a counter tablet, switching accounts has to be cheaper than sharing
/// one — a shop that finds handover slow will simply leave one login open all
/// day, and then every order is attributed to whoever that was. See
/// docs/auth-and-operator-plan.md §2.2.
///
/// So the device remembers names, and tapping one runs the sign-in for that
/// person alone. It remembers nothing that could sign anybody in by itself.
class DeviceAccounts extends ChangeNotifier {
  /// [prefs] is injectable so the roster can be tested without a platform
  /// channel behind it.
  // A named initialising formal would have to be `this._prefs`, and Dart has
  // no private named parameters.
  // ignore: prefer_initializing_formals
  DeviceAccounts({SharedPreferences? prefs}) : _prefs = prefs;


  static const _key = 'device_accounts';

  SharedPreferences? _prefs;
  List<DeviceAccount> _accounts = const [];
  bool _loaded = false;

  /// Most recently used first — on a busy counter the same two or three people
  /// sign in all day, and they should not have to hunt for themselves.
  List<DeviceAccount> get accounts => _accounts;

  bool get isLoaded => _loaded;

  /// Reads the roster in, at most once per launch.
  ///
  /// Every mutator waits on this first. Without that, a write arriving before
  /// the first read — `loadSession()` fires one the instant somebody signs in
  /// — would save its single entry over a roster it had never seen, and a
  /// tablet with four people on it would silently come back with one.
  Future<void> _ensureLoaded() => _loaded ? Future.value() : load();

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    _accounts = _decode(raw);
    _loaded = true;
    notifyListeners();
  }

  /// Records that this person signed in here. Called from `loadSession()`, so
  /// every route in — password, Google, passkey, and finishing registration —
  /// is covered by one call rather than four that can drift apart.
  Future<void> remember(AppUser user) async {
    await _ensureLoaded();
    final existing = _find(user.uid);
    final updated = (existing ??
            DeviceAccount(
              uid: user.uid,
              displayName: user.displayName,
              email: user.email,
            ))
        .copyWith(
      displayName: user.displayName,
      email: user.email,
      lastSignedIn: DateTime.now(),
    );
    await _write([updated, ..._accounts.where((a) => a.uid != user.uid)]);
  }

  /// Notes that a passkey on this device belongs to this person, so next time
  /// their name is enough to start the ceremony.
  Future<void> rememberPasskey(String uid, String credentialId) async {
    await _ensureLoaded();
    final existing = _find(uid);
    if (existing != null && existing.passkeyIds.contains(credentialId)) return;
    // Upserts, because a passkey sign-in learns the credential before
    // `loadSession()` has had a chance to record who it belongs to. The name
    // and address arrive a moment later and land on this same entry.
    if (existing == null) {
      await _write([
        DeviceAccount(
          uid: uid,
          displayName: '',
          email: '',
          passkeyIds: [credentialId],
          lastSignedIn: DateTime.now(),
        ),
        ..._accounts,
      ]);
      return;
    }
    await _write([
      for (final account in _accounts)
        if (account.uid == uid)
          account.copyWith(passkeyIds: [...account.passkeyIds, credentialId])
        else
          account,
    ]);
  }

  /// Drops the passkeys this device believed it held for somebody, after the
  /// authenticator has said it holds none of them. They were deleted from the
  /// device or from the account, and offering the fast path again would only
  /// fail again.
  Future<void> forgetPasskeys(String uid) async {
    await _ensureLoaded();
    final existing = _find(uid);
    if (existing == null || existing.passkeyIds.isEmpty) return;
    await _write([
      for (final account in _accounts)
        if (account.uid == uid)
          DeviceAccount(
            uid: account.uid,
            displayName: account.displayName,
            email: account.email,
            lastSignedIn: account.lastSignedIn,
          )
        else
          account,
    ]);
  }

  /// Takes somebody off this device. Nothing to do with their account, which
  /// is why the wording everywhere says "this device": a shop with a tablet
  /// going back to the leasing company needs this, and a shop with somebody
  /// leaving needs Store Staff instead.
  Future<void> forget(String uid) async {
    await _ensureLoaded();
    await _write(_accounts.where((a) => a.uid != uid).toList());
  }

  Future<void> forgetAll() => _write(const []);

  DeviceAccount? _find(String uid) {
    for (final account in _accounts) {
      if (account.uid == uid) return account;
    }
    return null;
  }

  Future<void> _write(List<DeviceAccount> accounts) async {
    _accounts = accounts;
    _loaded = true;
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      _key,
      jsonEncode([for (final a in accounts) a.toJson()]),
    );
  }

  static List<DeviceAccount> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final rows = jsonDecode(raw) as List<Object?>;
      return [
        for (final row in rows)
          if (row is Map<String, dynamic>) DeviceAccount.fromJson(row),
      ].where((a) => a.uid.isNotEmpty).toList();
    } catch (_) {
      // A roster that will not parse is a convenience that has broken, not a
      // failure worth showing anybody: the entry screen falls back to asking
      // who they are, which is where somebody with no roster starts anyway.
      return const [];
    }
  }
}
