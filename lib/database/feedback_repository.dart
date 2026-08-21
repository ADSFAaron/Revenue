import 'package:cloud_firestore/cloud_firestore.dart';

/// In-app feedback. Write-only from the app; read it from the Firebase console.
///
/// One document per submission rather than an ever-growing array on a single
/// per-store document — the same reason orders became one document each.
class FeedbackRepository {
  FeedbackRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<void> submit({
    required String storeId,
    required String message,
    required String version,
    required String build,
    String? uid,
  }) async {
    await _db.collection('feedback').add({
      'storeId': storeId,
      'feedback': message,
      'version': version,
      'build': build,
      'uid': uid,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
