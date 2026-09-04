import 'package:cloud_firestore/cloud_firestore.dart';

import 'session_apps.dart';

/// In-app feedback. Write-only from the app; read it from the Firebase console.
///
/// One document per submission rather than an ever-growing array on a single
/// per-store document — the same reason orders became one document each.
class FeedbackRepository {
  FeedbackRepository({FirebaseFirestore? firestore}) : _injected = firestore;

  final FirebaseFirestore? _injected;

  /// Read through the session that is current, not captured once.
  ///
  /// A counter tablet can hold several operators signed in at the same time,
  /// one Firebase app each, and handing the till over swaps which of them is
  /// current. A handle captured in the constructor would keep answering as the
  /// person who was at the till when this object was built. See SessionApps.
  FirebaseFirestore get _db =>
      _injected ?? FirebaseFirestore.instanceFor(app: sessionApps.active);

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
