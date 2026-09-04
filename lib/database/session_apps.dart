import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';

/// The signed-in operators this device is holding at once.
///
/// **Why this exists.** Firebase Authentication holds exactly one signed-in
/// user per `FirebaseApp`, so a device with one app can hold one session, and
/// changing hands means signing out and signing in again. Signing in needs the
/// network — a passkey goes through a Cloud Function to be turned into a
/// custom token — and taking orders offline is a supported path in this app.
/// So on the one thing this app is actually for, a counter tablet on a
/// kitchen's wifi, handing the till over was the operation most likely to be
/// impossible exactly when it was needed.
///
/// A second app is a second session. Firebase persists each app's user
/// locally, keyed by the app's name, so making a colleague who has signed in
/// here before the current operator again is a local read: no round trip, no
/// passkey ceremony, and it works with the wifi off.
///
/// **What it is not.** It is not a way around signing in. Every operator's
/// first sign-in on this device is the ordinary one, with everything the rules
/// and the relying party require. This only keeps the result.
class SessionApps {
  /// The three seams the tests need. Real callers pass none of them.
  SessionApps({
    SharedPreferences? prefs,
    Future<FirebaseApp> Function(String slot)? open,
    Future<void> Function(FirebaseApp app)? signOut,
  }) : // Dart has no private named parameters, so none of these three can be
       // an initialising formal, which is what the lint asks for.
       // ignore: prefer_initializing_formals
       _prefs = prefs,
       // ignore: prefer_initializing_formals
       _open = open,
       // ignore: prefer_initializing_formals
       _signOut = signOut;

  /// How many operators may be signed in at once.
  ///
  /// Each slot is another Firestore cache of the same shop, so a slot costs
  /// something real but small. Four covers a counter's shift and stops a year
  /// of casual staff turning into a year of caches.
  static const int maxSlots = 4;

  /// The first slot is the default `FirebaseApp` — the one
  /// `Firebase.initializeApp()` creates at launch. A shop with one person on
  /// the till therefore behaves exactly as it did before any of this existed:
  /// one app, created the same way, at the same point in the launch.
  static const String defaultSlot = 'default';

  static const List<String> slots = [
    defaultSlot,
    'operator1',
    'operator2',
    'operator3',
  ];

  static const _slotsKey = 'session.slots';
  static const _activeKey = 'session.active';

  SharedPreferences? _prefs;
  final Future<FirebaseApp> Function(String slot)? _open;
  final Future<void> Function(FirebaseApp app)? _signOut;

  /// uid to slot, for everybody this device is holding a session for.
  final Map<String, String> _byUid = {};

  /// Opened apps, kept for the life of the process. Firebase refuses to create
  /// an app under a name it already has, and deleting one while a Firestore
  /// stream is still winding down is a crash rather than a tidy-up — so a slot
  /// is emptied by signing its user out, never by disposing its app.
  final Map<String, FirebaseApp> _apps = {};

  String _activeSlot = defaultSlot;

  /// Bumped whenever the till changes hands.
  ///
  /// Anything holding a subscription — the root's watch on who is signed in,
  /// above all — has to let go of the old app's stream and take one from the
  /// new app. A stream is bound to the instance it came from, so without this
  /// the app would keep hearing about the operator who has just handed over.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// The app every repository reads through.
  ///
  /// Throws before the first slot is opened. That cannot happen in the app —
  /// `main()` opens one before `runApp` — and is worth throwing over rather
  /// than quietly answering with the default app, which at that point is a
  /// session belonging to nobody in particular.
  FirebaseApp get active {
    final app = _apps[_activeSlot];
    if (app == null) {
      throw StateError('No Firebase app is open for slot "$_activeSlot"');
    }
    return app;
  }

  bool get isReady => _apps.containsKey(_activeSlot);

  /// Whether tapping this person's name puts them straight in, or starts a
  /// sign-in. The entry screen asks before deciding what a tap means.
  bool holdsSessionFor(String uid) => _byUid.containsKey(uid);

  /// Everybody this device is currently holding a session for.
  List<String> get liveUids => _byUid.keys.toList();

  @visibleForTesting
  String get activeSlot => _activeSlot;

  /// Opens the slot the device was last using, and nothing else.
  ///
  /// Deliberately only one. Opening every remembered slot at launch would put
  /// three more Firebase initialisations on the path to the first frame to
  /// serve a switch that may never happen. A slot is opened when somebody taps
  /// the name in it, which is local and quick.
  Future<void> start() async {
    await _readSlots();
    final remembered = _prefs?.getString(_activeKey);
    _activeSlot = slots.contains(remembered) ? remembered! : defaultSlot;
    await _openSlot(_activeSlot);
  }

  /// Makes a session this device is already holding the current one.
  ///
  /// Returns false when there is no session for [uid], which is the caller's
  /// cue to sign them in the ordinary way. Everything this does is local, so
  /// it is the one path into the app that works with no connection at all.
  Future<bool> switchTo(String uid) async {
    final slot = _byUid[uid];
    if (slot == null) return false;
    await _openSlot(slot);
    await _makeActive(slot);
    return true;
  }

  /// Puts a slot under whoever is about to sign in, and makes it current.
  ///
  /// When every slot is taken, the operator who has been on this device
  /// longest gives theirs up — a till that has had four people on it today has
  /// had four people on it, and the fifth needs somewhere to be.
  Future<void> takeSlot() async {
    var slot = _freeSlot();
    if (slot == null) {
      final giving = _byUid.keys.first;
      slot = _byUid[giving]!;
      await _releaseSlot(slot);
      _byUid.remove(giving);
      await _writeSlots();
    }
    await _openSlot(slot);
    await _makeActive(slot);
  }

  /// Records that [uid] is the person signed in on the current slot.
  Future<void> claimActive(String uid) async {
    if (_byUid[uid] == _activeSlot) return;
    _byUid.removeWhere((_, slot) => slot == _activeSlot);
    _byUid[uid] = _activeSlot;
    await _writeSlots();
  }

  /// Gives up [uid]'s session and hands the till to whoever else this device
  /// is holding. Returns that person, or null when nobody is left.
  Future<String?> release(String uid) async {
    final slot = _byUid.remove(uid);
    if (slot != null) await _releaseSlot(slot);
    await _writeSlots();

    if (slot != null && slot != _activeSlot) {
      // Somebody signed out who was not the one at the till. Nothing to hand
      // over; the person in front of it stays where they are.
      return null;
    }
    if (_byUid.isEmpty) return null;
    final next = _byUid.keys.first;
    await switchTo(next);
    return next;
  }

  String? _freeSlot() {
    final taken = _byUid.values.toSet();
    for (final slot in slots) {
      if (!taken.contains(slot)) return slot;
    }
    return null;
  }

  Future<void> _makeActive(String slot) async {
    final changed = slot != _activeSlot;
    _activeSlot = slot;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_activeKey, slot);
    if (changed) revision.value++;
  }

  Future<void> _openSlot(String slot) async {
    if (_apps.containsKey(slot)) return;
    final open = _open;
    if (open == null) {
      throw StateError('SessionApps was built without an opener');
    }
    _apps[slot] = await open(slot);
  }

  /// Empties a slot without disposing its app. See [_apps].
  Future<void> _releaseSlot(String slot) async {
    final app = _apps[slot];
    if (app == null) return;
    try {
      await (_signOut ?? _signOutReal)(app);
    } catch (e) {
      // A sign-out that fails leaves a session this device is no longer
      // offering, which is untidy rather than unsafe: the slot is forgotten
      // either way, and the next person to be given it signs in over the top.
      debugPrint('Could not sign out slot "$slot": $e');
    }
  }

  static Future<void> _signOutReal(FirebaseApp app) =>
      FirebaseAuth.instanceFor(app: app).signOut();

  Future<void> _readSlots() async {
    _prefs ??= await SharedPreferences.getInstance();
    _byUid
      ..clear()
      ..addAll(_decode(_prefs!.getStringList(_slotsKey)));
  }

  Future<void> _writeSlots() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setStringList(_slotsKey, [
      for (final entry in _byUid.entries) '${entry.key} ${entry.value}',
    ]);
  }

  static Map<String, String> _decode(List<String>? rows) {
    final out = <String, String>{};
    for (final row in rows ?? const <String>[]) {
      final parts = row.split(' ');
      if (parts.length == 2 && slots.contains(parts[1])) {
        out[parts[0]] = parts[1];
      }
    }
    return out;
  }
}

/// Opens a slot's Firebase app and configures it, reusing one already
/// registered under that name.
///
/// Reuse rather than create-and-hope: `Firebase.initializeApp` throws
/// `duplicate-app` for a name it already knows, and a slot is opened again
/// every time somebody switches back to it.
///
/// Configuration happens here, once per app, because there is no other place
/// that sees every app exactly once. A slot that skipped it would be a session
/// with no offline cache — the whole reason for holding it — and no
/// attestation, which with App Check enforced is a refusal on the first read.
Future<FirebaseApp> openSessionApp(String slot, FirebaseOptions options) async {
  final existing = _appIfRegistered(slot);
  if (existing != null) return existing;

  final app = slot == SessionApps.defaultSlot
      ? await Firebase.initializeApp(options: options)
      : await Firebase.initializeApp(name: slot, options: options);

  FirebaseFirestore.instanceFor(app: app).settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  await configureAppCheckFor(app);
  return app;
}

FirebaseApp? _appIfRegistered(String slot) {
  try {
    return slot == SessionApps.defaultSlot ? Firebase.app() : Firebase.app(slot);
  } catch (_) {
    return null;
  }
}

/// Attests that requests from this app came from a genuine build.
///
/// Run for every slot, not only the first: a second session that skipped this
/// is a session whose every request arrives without a token, and with
/// enforcement on that is a refusal on the first screen.
Future<void> configureAppCheckFor(FirebaseApp app) async {
  const recaptchaKey = String.fromEnvironment('APP_CHECK_RECAPTCHA_KEY');
  if (kIsWeb && recaptchaKey.isEmpty) return;
  try {
    await FirebaseAppCheck.instanceFor(app: app).activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerWeb: recaptchaKey.isEmpty
          ? null
          : ReCaptchaEnterpriseProvider(recaptchaKey),
    );
  } catch (e) {
    debugPrint('App Check activation failed for ${app.name}: $e');
  }
}

/// The sessions this device is holding.
///
/// A singleton because there is one device. The repositories read the active
/// app through it rather than capturing a handle, which is what lets the till
/// change hands without rebuilding them.
final sessionApps = SessionApps(
  open: (slot) => openSessionApp(slot, DefaultFirebaseOptions.currentPlatform),
);
