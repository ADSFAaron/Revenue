import 'package:cloud_firestore/cloud_firestore.dart';

/// Who made a change, as it should read on the entry forever after.
///
/// The name is carried alongside the uid rather than looked up when the log is
/// displayed: staff leave, profiles get deleted, and an audit entry that
/// degrades to a bare uid a year later has lost most of its point.
class Actor {
  const Actor({this.uid, this.name});

  final String? uid;
  final String? name;
}

/// What was done. Stored by [id] so the wording can be reworded later without
/// rewriting history.
enum AuditAction {
  voidOrder('void_order', 'Voided an order'),
  editOrder('edit_order', 'Edited an order'),
  applyDiscount('apply_discount', 'Applied a discount'),
  editMenuPrice('edit_menu_price', 'Changed a menu price'),
  unknown('unknown', 'Unknown action');

  const AuditAction(this.id, this.label);

  final String id;
  final String label;

  static AuditAction fromId(String? id) => AuditAction.values
      .firstWhere((a) => a.id == id, orElse: () => AuditAction.unknown);
}

/// `stores/{storeId}/auditLogs/{logId}` — one entry per change worth tracing.
///
/// Only the four actions that can move money without a sale happening: voiding,
/// editing, discounting, and repricing. These are precisely the operations a
/// till discrepancy gets blamed on, and the entries exist so the answer is on
/// record rather than a matter of who remembers what.
///
/// Entries are append-only; the security rules refuse update and delete. A log
/// the people it covers can edit is not a log.
class AuditLog {
  const AuditLog({
    required this.id,
    required this.action,
    this.targetId,
    this.before,
    this.after,
    this.byUid,
    this.byName,
    this.at,
    this.note,
  });

  final String id;
  final AuditAction action;

  /// The order or menu item the entry is about.
  final String? targetId;

  /// The values either side of the change. Kept as free-form maps: what is
  /// worth recording differs per action, and a schema here would have to be
  /// migrated every time one is added.
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;

  final String? byUid;

  /// The name as it was at the time. Copied in rather than looked up later,
  /// so an entry still reads correctly after someone leaves and their profile
  /// is gone.
  final String? byName;

  final DateTime? at;
  final String? note;

  factory AuditLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    Map<String, dynamic>? map(String key) =>
        (data[key] as Map?)?.cast<String, dynamic>();

    return AuditLog(
      id: doc.id,
      action: AuditAction.fromId(data['action'] as String?),
      targetId: data['targetId'] as String?,
      before: map('before'),
      after: map('after'),
      byUid: data['byUid'] as String?,
      byName: data['byName'] as String?,
      at: (data['at'] as Timestamp?)?.toDate(),
      note: data['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'action': action.id,
        'targetId': targetId,
        'before': before,
        'after': after,
        'byUid': byUid,
        'byName': byName,
        'note': note,
      };

  /// A one-line summary for the history list.
  ///
  /// [who] is the name looked up from the store's staff at display time, so a
  /// person who has since been renamed reads as themselves. [byName] is the
  /// copy taken when the entry was written, and it is the better answer in
  /// exactly one case — an account that has since been deleted, where nothing
  /// can be looked up but the trail should still say who it was.
  String summaryBy(String? who) {
    final name = (who?.isNotEmpty == true ? who : null) ??
        (byName?.isNotEmpty == true ? byName : null) ??
        'Someone';
    return '$name ${action.label.toLowerCase()}';
  }
}
