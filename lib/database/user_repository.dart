import 'package:cloud_firestore/cloud_firestore.dart';

import 'session_apps.dart';

import '../models/app_user.dart';
import 'auth_repository.dart';

/// Everything that touches `users/{uid}`.
///
/// Documents are keyed by the Firebase Auth uid. Nothing outside this class
/// should assume anything about how a user is stored.
class UserRepository {
  UserRepository({FirebaseFirestore? firestore, AuthRepository? auth})
      : _injected = firestore,
        _auth = auth ?? AuthRepository();

  final FirebaseFirestore? _injected;

  /// Read through the session that is current, not captured once.
  ///
  /// A counter tablet can hold several operators signed in at the same time,
  /// one Firebase app each, and handing the till over swaps which of them is
  /// current. A handle captured in the constructor would keep answering as the
  /// person who was at the till when this object was built. See SessionApps.
  FirebaseFirestore get _db =>
      _injected ?? FirebaseFirestore.instanceFor(app: sessionApps.active);

  /// Only for resolving "who is signed in" — who that person *is* lives in
  /// `users/{uid}`, which is this class's business; the uid itself is not.
  final AuthRepository _auth;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  /// One in-flight or settled lookup per store, dropped whenever this class
  /// writes a user document — which is the only way a name in it can change.
  final Map<String, Future<StaffNames>> _names = {};

  Future<AppUser?> fetch(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.exists ? AppUser.fromDoc(doc) : null;
  }

  Stream<AppUser?> watchCurrent() {
    final uid = _auth.currentUid;
    if (uid == null) return Stream.value(null);
    return _users
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);
  }

  Future<void> create(AppUser user) async {
    _names.remove(user.storeId);
    await _users.doc(user.uid).set({
      ...user.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateDisplayName(String uid, String displayName) async {
    _names.clear();
    await _users.doc(uid).update({
      'displayName': displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateRole(String uid, UserRole role) async {
    _names.clear();
    await _users.doc(uid).update({
      'role': role.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes somebody from the store, or puts them back.
  ///
  /// Not a delete and not a cleared `storeId`: the rules refuse both, and both
  /// would be one-way. Their orders stay either way — those are the shop's
  /// books, not the person's.
  Future<void> setActive(String uid, bool active) async {
    _names.clear();
    await _users.doc(uid).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// The store's staff list, found by reverse lookup. This replaces the old
  /// `users` / `users2` arrays that were kept on the store document and drifted
  /// out of sync with each other.
  ///
  /// Removed members are still in it, at the bottom: somebody has to be able
  /// to put them back, and a list they have vanished from offers no way to.
  Stream<List<AppUser>> watchStaff(String storeId) => _users
      .where('storeId', isEqualTo: storeId)
      .snapshots()
      .map((snap) => snap.docs.map(AppUser.fromDoc).toList()
        ..sort((a, b) => a.active == b.active
            ? a.role.index.compareTo(b.role.index)
            : (a.active ? -1 : 1)));


  /// Names for the uids stamped on orders and audit entries.
  ///
  /// Looked up rather than copied onto the documents themselves: an order is
  /// the shop's book and does not change, but a person's name does, and a name
  /// frozen into a thousand orders is a thousand places a correction has to
  /// reach. The cost is one small query per store, cached here.
  Future<StaffNames> staffNames(String storeId) =>
      _names[storeId] ??= _users
          .where('storeId', isEqualTo: storeId)
          .get()
          .then(
            (snap) => StaffNames({
              for (final doc in snap.docs)
                doc.id: AppUser.fromDoc(doc).displayLabel,
            }),
          )
          // A failed lookup must not be cached, or a moment without a
          // connection would mean "Former staff" against every order for the
          // rest of the session.
          .catchError((Object error) {
            _names.remove(storeId);
            throw error;
          });
}

/// Who the uids on a store's orders and audit entries belong to.
///
/// The interesting case is the one that does not resolve. `functions/src/
/// account.ts` deletes a departing person's user document and leaves their
/// orders — those are the shop's books, not theirs — so a uid pointing at
/// nobody is the expected end state, not a fault. It must read as a sentence:
/// a blank says the order was taken by nobody, and a raw uid says nothing at
/// all to the person holding the tablet.
class StaffNames {
  const StaffNames(this._byUid);

  const StaffNames.empty() : _byUid = const {};

  final Map<String, String> _byUid;

  /// The name to show for a uid, whatever state it is in.
  ///
  /// [missing] is what an order carries when it predates `createdBy`, or came
  /// off the offline queue before that path stamped one.
  String labelFor(
    String? uid, {
    String missing = 'Not recorded',
    String departed = 'Former staff',
  }) {
    if (uid == null || uid.isEmpty) return missing;
    return _byUid[uid] ?? departed;
  }

  /// True when this uid belongs to somebody the store still has on file.
  bool knows(String? uid) => uid != null && _byUid.containsKey(uid);
}
