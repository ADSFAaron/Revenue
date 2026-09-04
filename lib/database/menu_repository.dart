import 'package:cloud_firestore/cloud_firestore.dart';

import 'session_apps.dart';

import '../models/audit_log.dart';
import '../models/menu_item.dart';
import 'audit_log_repository.dart';

/// Everything that touches `stores/{storeId}/menuItems/{itemId}`.
///
/// The menu is a subcollection rather than an array on the store document so
/// that each dish keeps a stable id across renames and price changes.
class MenuRepository {
  MenuRepository({FirebaseFirestore? firestore, AuditLogRepository? auditLogs})
      : _injected = firestore,
        _auditLogs = auditLogs ?? AuditLogRepository();

  final FirebaseFirestore? _injected;

  /// Read through the session that is current, not captured once.
  ///
  /// A counter tablet can hold several operators signed in at the same time,
  /// one Firebase app each, and handing the till over swaps which of them is
  /// current. A handle captured in the constructor would keep answering as the
  /// person who was at the till when this object was built. See SessionApps.
  FirebaseFirestore get _db =>
      _injected ?? FirebaseFirestore.instanceFor(app: sessionApps.active);
  final AuditLogRepository _auditLogs;

  CollectionReference<Map<String, dynamic>> _items(String storeId) =>
      _db.collection('stores').doc(storeId).collection('menuItems');

  // There is deliberately no starter menu and no default category list here.
  // Registration used to seed six dishes and three categories into every new
  // store; that menu belonged to nobody, and it invited somebody to ring up a
  // sale against a dish this kitchen has never sold. A new store starts empty,
  // and Store Settings → Edit Menu is where it stops being empty.
  /// Every dish including retired ones — the menu editor needs these so a
  /// retired dish can be brought back.
  Stream<List<MenuItem>> watchAll(String storeId) =>
      _items(storeId).snapshots().map(_sorted);

  Future<List<MenuItem>> fetchActive(String storeId) async =>
      _sorted(await _items(storeId).where('isActive', isEqualTo: true).get());

  Future<List<MenuItem>> fetchAll(String storeId) async =>
      _sorted(await _items(storeId).get());

  List<MenuItem> _sorted(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map(MenuItem.fromDoc).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Future<String> add(String storeId, MenuItem item) async {
    final ref = await _items(storeId).add({
      ...item.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Saves an edited dish, recording the change when it moves the price.
  ///
  /// Pass [previous] and [by] to have a repricing show up in the audit log.
  /// Only the price is logged: a rename or a new icon cannot change what a
  /// till takes, and logging every keystroke would bury the entries that
  /// matter.
  Future<void> update(
    String storeId,
    MenuItem item, {
    MenuItem? previous,
    Actor? by,
  }) async {
    final data = {
      ...item.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final repriced = previous != null && previous.price != item.price;
    if (!repriced) {
      await _items(storeId).doc(item.id).update(data);
      return;
    }

    // Batched so the new price and the record of it land together. Two separate
    // writes would let a dropped connection leave a changed price with nothing
    // saying who changed it — which is the one case the entry exists for.
    final batch = _db.batch();
    batch.update(_items(storeId).doc(item.id), data);
    final (logRef, logData) = _auditLogs.entryFor(
      storeId,
      AuditLog(
        id: '',
        action: AuditAction.editMenuPrice,
        targetId: item.id,
        before: {'name': previous.name, 'price': previous.price},
        after: {'name': item.name, 'price': item.price},
        byUid: by?.uid,
        byName: by?.name,
      ),
    );
    batch.set(logRef, logData);
    await batch.commit();
  }

  /// Retires a dish. Never deletes it: past orders reference this id, and a
  /// missing item turns them into rows nobody can interpret.
  Future<void> deactivate(String storeId, String itemId) =>
      _setActive(storeId, itemId, false);

  Future<void> reactivate(String storeId, String itemId) =>
      _setActive(storeId, itemId, true);

  Future<void> _setActive(String storeId, String itemId, bool isActive) =>
      _items(storeId).doc(itemId).update({
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Persists a drag-to-reorder as consecutive `sortOrder` values.
  Future<void> reorder(String storeId, List<MenuItem> ordered) async {
    final batch = _db.batch();
    for (var i = 0; i < ordered.length; i++) {
      batch.update(_items(storeId).doc(ordered[i].id), {
        'sortOrder': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
