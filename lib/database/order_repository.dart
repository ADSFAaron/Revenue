// cloud_firestore exports an `Order` enum for index definitions; ours is the
// domain object.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import 'session_apps.dart';

import '../models/audit_log.dart';
import '../models/order.dart';
import '../models/order_draft.dart';
import '../models/store.dart';
import 'audit_log_repository.dart';

/// Everything that touches `stores/{storeId}/orders/{orderId}`, plus the two
/// documents that must move with it: the day's order-number counter and the
/// day's rollup.
///
/// One order is one document. The previous design kept every order of a store
/// inside a single array field, which rewrote the whole history on each sale
/// and would hit Firestore's 1 MB per-document ceiling within months.
class OrderRepository {
  OrderRepository({FirebaseFirestore? firestore, AuditLogRepository? auditLogs})
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

  DocumentReference<Map<String, dynamic>> _store(String storeId) =>
      _db.collection('stores').doc(storeId);

  CollectionReference<Map<String, dynamic>> _orders(String storeId) =>
      _store(storeId).collection('orders');

  DocumentReference<Map<String, dynamic>> _counter(
          String storeId, String businessDate) =>
      _store(storeId).collection('counters').doc(businessDate);

  DocumentReference<Map<String, dynamic>> _stats(
          String storeId, String businessDate) =>
      _store(storeId).collection('dailyStats').doc(businessDate);

  // ---------------------------------------------------------------- writing

  /// A document id for an order that has not been written yet.
  ///
  /// Client-generated, which Firestore is happy to do offline — it is what
  /// lets the offline queue name an order before it can send it, and so what
  /// makes sending it twice harmless.
  String newOrderId(String storeId) => _orders(storeId).doc().id;

  /// Writes a new order, takes the next order number for its trading day and
  /// folds it into that day's rollup — all in one transaction, so two phones
  /// ringing up at the same moment cannot take the same number or lose a sale
  /// from the totals.
  ///
  /// Returns the order number that was assigned.
  Future<int> submit({
    required Store store,
    required OrderDraft draft,
    String? createdBy,
    String? orderId,
  }) async {
    final businessDate = store.businessDateOf(draft.placedAt);
    final orderRef = orderId == null
        ? _orders(store.id).doc()
        : _orders(store.id).doc(orderId);
    final counterRef = _counter(store.id, businessDate);

    return _db.runTransaction<int>((tx) async {
      // All reads before any write, and this one first: an order sent from the
      // offline queue carries the id it was given on the device, so a flush
      // interrupted between the commit and the queue being cleaned up sends it
      // again. Finding it already there means the sale is already rung up —
      // going on would take a second order number and add the money twice.
      if (orderId != null) {
        final existing = await tx.get(orderRef);
        if (existing.exists) {
          return (existing.data()?['orderNo'] as num?)?.toInt() ?? 0;
        }
      }

      final counterSnap = await tx.get(counterRef);
      final orderNo =
          (counterSnap.data()?['nextOrderNo'] as num?)?.toInt() ?? 1;

      final order = draft.toOrder(
        id: orderRef.id,
        orderNo: orderNo,
        store: store,
        createdBy: createdBy,
      );

      tx.set(orderRef, {
        ...order.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(counterRef, {'nextOrderNo': orderNo + 1});
      _applyStats(tx, store.id, order, 1);

      return orderNo;
    });
  }

  /// Replaces an existing order. The old order's contribution is subtracted
  /// from its rollup before the new one is added, so an edit never leaves the
  /// day's totals double-counted.
  ///
  /// If the edit moves the order into a different trading day it is given a
  /// fresh number from that day's counter — order numbers restart daily, so
  /// carrying the old one over would collide.
  Future<int> replace({
    required Store store,
    required String orderId,
    required OrderDraft draft,
    Actor? by,
  }) async {
    final orderRef = _orders(store.id).doc(orderId);
    final newBusinessDate = store.businessDateOf(draft.placedAt);

    return _db.runTransaction<int>((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) {
        throw StateError('Order $orderId no longer exists');
      }
      final existing = Order.fromDoc(snap);
      if (existing.isVoided) {
        throw StateError('A voided order cannot be edited');
      }

      // All reads must happen before any write inside a transaction.
      var orderNo = existing.orderNo;
      DocumentReference<Map<String, dynamic>>? counterRef;
      if (newBusinessDate != existing.businessDate) {
        counterRef = _counter(store.id, newBusinessDate);
        final counterSnap = await tx.get(counterRef);
        orderNo = (counterSnap.data()?['nextOrderNo'] as num?)?.toInt() ?? 1;
      }

      final updated = draft.toOrder(
        id: orderId,
        orderNo: orderNo,
        store: store,
        createdBy: existing.createdBy,
      );

      _applyStats(tx, store.id, existing, -1);
      tx.update(orderRef, {
        ...updated.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (counterRef != null) {
        tx.set(counterRef, {'nextOrderNo': orderNo + 1});
      }
      _applyStats(tx, store.id, updated, 1);
      _recordAudit(
        tx,
        store.id,
        AuditLog(
          id: '',
          action: AuditAction.editOrder,
          targetId: orderId,
          before: _auditSnapshot(existing),
          after: _auditSnapshot(updated),
          byUid: by?.uid,
          byName: by?.name,
        ),
      );

      return orderNo;
    });
  }

  /// Marks an order void and backs it out of the day's totals.
  ///
  /// The document is never deleted — a cancelled sale that leaves no trace is
  /// exactly the gap that makes till discrepancies unarguable.
  Future<void> voidOrder({
    required Store store,
    required String orderId,
    required Actor by,
    String? reason,
  }) async {
    final orderRef = _orders(store.id).doc(orderId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) {
        throw StateError('Order $orderId no longer exists');
      }
      final order = Order.fromDoc(snap);
      if (order.isVoided) return;

      tx.update(orderRef, {
        'status': OrderStatus.voided.id,
        'voidedAt': FieldValue.serverTimestamp(),
        'voidedBy': by.uid,
        'voidReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _applyStats(tx, store.id, order, -1);
      tx.set(
        _stats(store.id, order.businessDate),
        {
          'businessDate': order.businessDate,
          'voidedCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _recordAudit(
        tx,
        store.id,
        AuditLog(
          id: '',
          action: AuditAction.voidOrder,
          targetId: orderId,
          before: _auditSnapshot(order),
          byUid: by.uid,
          byName: by.name,
          note: reason,
        ),
      );
    });
  }

  /// Appends an audit entry as part of the caller's transaction.
  ///
  /// In the transaction on purpose: a void that commits without its record, or
  /// a record without the void, is exactly the discrepancy the log exists to
  /// settle.
  void _recordAudit(Transaction tx, String storeId, AuditLog log) {
    final (ref, data) = _auditLogs.entryFor(storeId, log);
    tx.set(ref, data);
  }

  /// The parts of an order worth freezing into an audit entry.
  ///
  /// Not the whole document: every line item on both sides of every edit would
  /// bloat the log for detail nobody reads. These are the fields a till
  /// discrepancy actually turns on.
  static Map<String, dynamic> _auditSnapshot(Order order) => {
        'orderNo': order.orderNo,
        'businessDate': order.businessDate,
        'total': order.total,
        'discountAmount': order.discountAmount,
        'itemCount': order.items.length,
      };

  /// Folds [order] into (sign 1) or out of (sign -1) its day's rollup.
  ///
  /// Uses [FieldValue.increment] throughout, which is atomic server-side, so
  /// this needs no read and cannot lose a concurrent update.
  void _applyStats(Transaction tx, String storeId, Order order, int sign) {
    FieldValue inc(num value) => FieldValue.increment(sign * value);

    // Totals per key are accumulated first: one FieldValue.increment per key
    // per transaction, because writing the same map key twice in one payload
    // would keep only the last value rather than adding them up.
    final itemTotals = <String, _LineTotals>{};
    final categoryTotals = <String, _LineTotals>{};
    for (final line in order.items) {
      final itemKey = line.itemId.isEmpty ? 'unknown' : line.itemId;
      (itemTotals[itemKey] ??= _LineTotals(line.name)).add(line);

      final categoryKey = line.categoryId ?? 'uncategorized';
      (categoryTotals[categoryKey] ??= _LineTotals(categoryKey)).add(line);
    }

    final byItem = itemTotals.map((key, totals) => MapEntry(key, {
          'name': totals.name,
          'qty': inc(totals.qty),
          'revenue': inc(totals.revenue),
          'cost': inc(totals.cost),
        }));
    final byCategory = categoryTotals.map((key, totals) => MapEntry(key, {
          'qty': inc(totals.qty),
          'revenue': inc(totals.revenue),
          'cost': inc(totals.cost),
        }));

    tx.set(
      _stats(storeId, order.businessDate),
      {
        'businessDate': order.businessDate,
        'orderCount': inc(1),
        'guestCount': inc(order.guestCount),
        'revenue': inc(order.total),
        'cost': inc(order.totalCost),
        'discountTotal': inc(order.discountAmount),
        'taxTotal': inc(order.taxAmount),
        'commissionTotal': inc(order.commissionAmount),
        'byHour': {
          order.hourOfDay.toString(): {
            'orders': inc(1),
            'revenue': inc(order.total),
            'guests': inc(order.guestCount),
          },
        },
        'byChannel': {
          order.channel.id: {
            'orders': inc(1),
            'revenue': inc(order.total),
            'guests': inc(order.guestCount),
          },
        },
        'byPayment': {
          order.paymentMethodId: {
            'orders': inc(1),
            'revenue': inc(order.total),
          },
        },
        'byItem': byItem,
        'byCategory': byCategory,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ---------------------------------------------------------------- reading

  Future<Order?> fetch(String storeId, String orderId) async {
    final doc = await _orders(storeId).doc(orderId).get();
    return doc.exists ? Order.fromDoc(doc) : null;
  }

  Stream<Order?> watch(String storeId, String orderId) => _orders(storeId)
      .doc(orderId)
      .snapshots()
      .map((doc) => doc.exists ? Order.fromDoc(doc) : null);

  /// The most recent orders, newest first. Backed by the automatic single-field
  /// index on `placedAt`.
  Stream<List<Order>> watchRecent(String storeId, {int limit = 20}) =>
      _orders(storeId)
          .orderBy('placedAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(Order.fromDoc).toList());

  /// One trading day's orders, oldest first.
  Stream<List<Order>> watchDay(String storeId, String businessDate) =>
      _orders(storeId)
          .where('businessDate', isEqualTo: businessDate)
          .orderBy('placedAt')
          .snapshots()
          .map((snap) => snap.docs.map(Order.fromDoc).toList());

  /// A page of history, newest first. Pass the last order of the previous page
  /// as [startAfter] to continue.
  Future<List<Order>> fetchPage(
    String storeId, {
    int limit = 30,
    Order? startAfter,
  }) async {
    var query =
        _orders(storeId).orderBy('placedAt', descending: true).limit(limit);
    if (startAfter != null) {
      query = query.startAfter([Timestamp.fromDate(startAfter.placedAt)]);
    }
    final snap = await query.get();
    return snap.docs.map(Order.fromDoc).toList();
  }

  /// Every order between two trading days, inclusive.
  Future<List<Order>> fetchRange(
    String storeId, {
    required String fromBusinessDate,
    required String toBusinessDate,
  }) async {
    final snap = await _orders(storeId)
        .where('businessDate', isGreaterThanOrEqualTo: fromBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: toBusinessDate)
        .orderBy('businessDate')
        .orderBy('placedAt')
        .get();
    return snap.docs.map(Order.fromDoc).toList();
  }
}

/// Running totals for one rollup key while building a stats delta.
class _LineTotals {
  _LineTotals(this.name);

  final String name;
  int qty = 0;
  int revenue = 0;
  int cost = 0;

  void add(OrderLine line) {
    qty += line.qty;
    revenue += line.lineRevenue;
    cost += line.lineCost;
  }
}
