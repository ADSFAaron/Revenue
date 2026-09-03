import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_draft.dart';
import '../models/pending_order.dart';
import '../models/store.dart';
import 'connection_status.dart';
import 'data_exception.dart';
import 'order_repository.dart';
import 'store_repository.dart';

/// Orders rung up with no connection, kept on this device until there is one.
///
/// See [PendingOrder] for why a queue is needed at all. This holds the list,
/// persists it, and sends it — in that order of importance: an order that is
/// only in memory is one process kill away from being a sale nobody can
/// account for.
///
/// Deliberately device-local and never synced. Two tills that both go offline
/// keep their own queues and both drain when they reconnect; nothing here is
/// shared, so there is nothing to merge.
class PendingOrderQueue extends ValueNotifier<List<PendingOrder>> {
  PendingOrderQueue({
    required OrderRepository orders,
    required StoreRepository stores,
  })  : _orders = orders,
        _stores = stores,
        super(const []);

  static const _key = 'pendingOrders.v1';

  final OrderRepository _orders;
  final StoreRepository _stores;

  bool _sending = false;
  bool _listening = false;

  /// True while a flush is in flight. One at a time, always: two overlapping
  /// flushes would race to send the same order.
  bool get isSending => _sending;

  int get length => value.length;
  bool get isEmpty => value.isEmpty;

  /// Reads the queue back off the device and starts draining it whenever the
  /// connection returns.
  Future<void> start() async {
    await _load();
    if (!_listening) {
      _listening = true;
      connectionStatus.addListener(_onConnectionChanged);
    }
    // The connection may already be up — an app relaunched after the wifi came
    // back gets no change notification, only a queue that is already stale.
    if (!connectionStatus.isOffline) unawaited(flush());
  }

  void stop() {
    if (!_listening) return;
    _listening = false;
    connectionStatus.removeListener(_onConnectionChanged);
  }

  void _onConnectionChanged() {
    if (!connectionStatus.isOffline) unawaited(flush());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = PendingOrder.decode(prefs.getString(_key));
    } catch (_) {
      // An unreadable store leaves the queue empty for this run rather than
      // stopping the app; nothing is deleted, so a later write is what fixes
      // or overwrites it.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, PendingOrder.encode(value));
    } catch (_) {
      // Kept in memory for this session at least. There is nothing useful to
      // tell the person at the till here — the order is on screen either way.
    }
  }

  /// Puts an order on the queue. The id is allocated now, on this device, so
  /// that sending it later is idempotent.
  ///
  /// [createdBy] is taken now for the same reason the id is — see
  /// [PendingOrder.createdBy]. Who was at the till when the order was rung up
  /// is not a fact the flush can recover later.
  Future<PendingOrder> add(
    String storeId,
    OrderDraft draft, {
    String? createdBy,
  }) async {
    final pending = PendingOrder(
      id: _orders.newOrderId(storeId),
      storeId: storeId,
      queuedAt: DateTime.now(),
      draft: draft,
      createdBy: createdBy,
    );
    value = [...value, pending];
    await _save();
    return pending;
  }

  /// Drops one without sending it — a mis-rung order that never became a sale.
  Future<void> discard(String id) async {
    value = value.where((p) => p.id != id).toList();
    await _save();
  }

  /// Sends everything it can, oldest first.
  ///
  /// Returns how many went. Stops at the first order that fails for a reason
  /// that will fail again — no connection — and leaves the rest queued;
  /// carrying on would just be a row of identical failures.
  Future<int> flush() async {
    if (_sending || value.isEmpty) return 0;
    _sending = true;
    notifyListeners();

    var sent = 0;
    try {
      // One store fetch for the whole drain rather than one per order. Offline
      // this comes from the cache, which is the same store the orders were
      // rung up against.
      final byStore = <String, Store?>{};

      for (final pending in [...value]) {
        var store = byStore[pending.storeId];
        if (store == null) {
          try {
            store = await _stores.fetch(pending.storeId);
          } catch (_) {
            // No store means no tax rate and no trading day, so there is
            // nothing to price this against. It stays queued.
            break;
          }
          byStore[pending.storeId] = store;
        }
        if (store == null) break;

        try {
          await _orders.submit(
            store: store,
            draft: pending.draft,
            createdBy: pending.createdBy,
            orderId: pending.id,
          );
          await discard(pending.id);
          sent++;
        } catch (e) {
          final failure = describeFailure(e).failure;
          if (failure == DataFailure.offline ||
              failure == DataFailure.contention) {
            // Still no connection, or somebody else held the counter. Both are
            // worth retrying later, unchanged.
            break;
          }
          // Anything else — a refused write, a store that no longer exists —
          // would fail identically on every retry, so the order stays queued
          // and visible rather than being dropped silently. The screen showing
          // the queue is what surfaces it.
          break;
        }
      }
    } finally {
      _sending = false;
      notifyListeners();
    }
    return sent;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
