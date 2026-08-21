import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/audit_log.dart';

/// Reads and appends `stores/{storeId}/auditLogs/{logId}`.
///
/// Writes go in through [entryFor] and are attached to the same transaction
/// that makes the change, so an order cannot be voided without the record of
/// it being written in the same breath. A log written afterwards, from a
/// second call, is a log that goes missing exactly when the network drops
/// halfway through.
class AuditLogRepository {
  AuditLogRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _logs(String storeId) =>
      _db.collection('stores').doc(storeId).collection('auditLogs');

  /// A reference and payload ready to be written inside a caller's
  /// transaction.
  (DocumentReference<Map<String, dynamic>>, Map<String, dynamic>) entryFor(
    String storeId,
    AuditLog log,
  ) =>
      (
        _logs(storeId).doc(),
        {
          ...log.toMap(),
          'at': FieldValue.serverTimestamp(),
        }
      );

  /// For changes that are not already inside a transaction.
  Future<void> record(String storeId, AuditLog log) async {
    final (ref, data) = entryFor(storeId, log);
    await ref.set(data);
  }

  /// Newest first. Readable only by managers, per the security rules.
  Stream<List<AuditLog>> watchRecent(String storeId, {int limit = 100}) =>
      _logs(storeId)
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(AuditLog.fromDoc).toList());
}
