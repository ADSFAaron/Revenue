import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import 'auth_repository.dart';

/// Everything that touches `users/{uid}`.
///
/// Documents are keyed by the Firebase Auth uid. Nothing outside this class
/// should assume anything about how a user is stored.
class UserRepository {
  UserRepository({FirebaseFirestore? firestore, AuthRepository? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? AuthRepository();

  final FirebaseFirestore _db;

  /// Only for resolving "who is signed in" — who that person *is* lives in
  /// `users/{uid}`, which is this class's business; the uid itself is not.
  final AuthRepository _auth;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  Future<AppUser?> fetch(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.exists ? AppUser.fromDoc(doc) : null;
  }

  /// The signed-in user's profile, or null when signed out.
  Future<AppUser?> fetchCurrent() async {
    final uid = _auth.currentUid;
    return uid == null ? null : fetch(uid);
  }

  Stream<AppUser?> watchCurrent() {
    final uid = _auth.currentUid;
    if (uid == null) return Stream.value(null);
    return _users
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);
  }

  /// Convenience for the many screens that only need the store id.
  Future<String?> currentStoreId() async => (await fetchCurrent())?.storeId;

  Future<void> create(AppUser user) async {
    await _users.doc(user.uid).set({
      ...user.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateDisplayName(String uid, String displayName) async {
    await _users.doc(uid).update({
      'displayName': displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateRole(String uid, UserRole role) async {
    await _users.doc(uid).update({
      'role': role.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// The store's staff list, found by reverse lookup. This replaces the old
  /// `users` / `users2` arrays that were kept on the store document and drifted
  /// out of sync with each other.
  Stream<List<AppUser>> watchStaff(String storeId) => _users
      .where('storeId', isEqualTo: storeId)
      .snapshots()
      .map((snap) => snap.docs.map(AppUser.fromDoc).toList()
        ..sort((a, b) => a.role.index.compareTo(b.role.index)));

  Future<List<AppUser>> fetchStaff(String storeId) async {
    final snap = await _users.where('storeId', isEqualTo: storeId).get();
    return snap.docs.map(AppUser.fromDoc).toList()
      ..sort((a, b) => a.role.index.compareTo(b.role.index));
  }

  Future<int> staffCount(String storeId) async {
    final snap =
        await _users.where('storeId', isEqualTo: storeId).count().get();
    return snap.count ?? 0;
  }
}
