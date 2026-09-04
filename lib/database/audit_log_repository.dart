import 'package:cloud_firestore/cloud_firestore.dart';

import 'session_apps.dart';

import '../models/audit_log.dart';

/// Reads and appends `stores/{storeId}/auditLogs/{logId}`.
///
/// Writes go in through [entryFor] and are attached to the same transaction
/// that makes the change, so an order cannot be voided without the record of
/// it being written in the same breath. A log written afterwards, from a
/// second call, is a log that goes missing exactly when the network drops
/// halfway through.
class AuditLogRepository {
  AuditLogRepository({FirebaseFirestore? firestore}) : _injected = firestore;

  final FirebaseFirestore? _injected;

  /// Read through the session that is current, not captured once.
  ///
  /// A counter tablet can hold several operators signed in at the same time,
  /// one Firebase app each, and handing the till over swaps which of them is
  /// current. A handle captured in the constructor would keep answering as the
  /// person who was at the till when this object was built. See SessionApps.
  FirebaseFirestore get _db =>
      _injected ?? FirebaseFirestore.instanceFor(app: sessionApps.active);

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

  /// Newest first. Readable only by managers, per the security rules.
  Stream<List<AuditLog>> watchRecent(String storeId, {int limit = 100}) =>
      _logs(storeId)
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(AuditLog.fromDoc).toList());
}
