import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/database/order_repository.dart';
import 'package:Revenue/database/pending_order_queue.dart';
import 'package:Revenue/database/repositories.dart' show pendingOrders;
import 'package:Revenue/models/menu_item.dart';
import 'package:Revenue/models/order.dart';
import 'package:Revenue/models/order_draft.dart';
import 'package:Revenue/models/store.dart';
import 'package:Revenue/widgets/pending_orders.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shop.dart';

/// Orders rung up with no connection.
///
/// This is the part of the app with the least margin for error in it. An order
/// that is only in memory is one process kill away from being a sale nobody
/// can account for; an order sent twice is money the shop did not take. The
/// queue has to be durable, it has to drain in order, and — because a flush
/// interrupted between the commit and the clean-up will run again — sending
/// the same order twice has to be harmless.
///
/// Nothing here needs a real dropped connection. What the queue reacts to is a
/// `unavailable` failure coming back from a write, and that is a thing a fake
/// repository can produce exactly.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A shop whose till can be taken offline and put back.
  Future<(Shop, _FlakyOrders, PendingOrderQueue)> tillWithAQueue() async {
    final shop = await Shop.opened();
    final orders = _FlakyOrders(shop);
    final queue = PendingOrderQueue(orders: orders, stores: shop.stores);
    return (shop, orders, queue);
  }

  OrderDraft draftOf(MenuItem dish, {int qty = 1, DateTime? at}) =>
      OrderDraft(
        placedAt: at ?? DateTime.now(),
        items: [
          OrderLine(
            itemId: dish.id,
            name: dish.name,
            unitPrice: dish.price,
            qty: qty,
          ),
        ],
      );

  group('taking an order with no connection', () {
    test('it goes on the queue rather than being lost', () async {
      final (shop, _, queue) = await tillWithAQueue();
      final tea = await shop.addDish('Tea', price: 30);

      await queue.add(shop.store.id, draftOf(tea));

      expect(queue.length, 1);
      expect(await shop.ordersNow(), isEmpty);
      expect((await shop.dayStatsNow()).revenue, 0,
          reason: 'a queued order has not been taken yet');
    });

    test('it is given its id now, on this device', () async {
      // Not by the server later. The id is what makes sending it twice
      // harmless, so it has to exist before there is any connection to ask.
      final (shop, _, queue) = await tillWithAQueue();
      final tea = await shop.addDish('Tea', price: 30);

      final pending = await queue.add(shop.store.id, draftOf(tea));

      expect(pending.id, isNotEmpty);
      expect(pending.storeId, shop.store.id);
    });

    test('and it survives the app being killed', () async {
      // The whole reason it is written to disk. A queue that lives only in
      // memory turns a crash into a sale nobody can account for.
      final (shop, orders, queue) = await tillWithAQueue();
      final tea = await shop.addDish('Tea', price: 30);
      await queue.add(shop.store.id, draftOf(tea, qty: 3));

      // A fresh queue over the same device storage is what a relaunch is.
      final afterRestart =
          PendingOrderQueue(orders: orders, stores: shop.stores);
      orders.offline = true;
      await afterRestart.start();

      expect(afterRestart.length, 1);
      expect(afterRestart.value.single.draft.items.single.qty, 3);
    });

    test('who rang it up is remembered with it', () async {
      // Not recoverable at flush time: by then the till may have changed
      // hands, and the order would be attributed to whoever is holding it.
      final (shop, _, queue) = await tillWithAQueue();
      final tea = await shop.addDish('Tea', price: 30);

      await queue.add(shop.store.id, draftOf(tea), createdBy: 'uid-cook');

      expect(queue.value.single.createdBy, 'uid-cook');
    });
  });

  group('the connection coming back', () {
    test('drains the queue into real orders', () async {
      final (shop, orders, queue) = await tillWithAQueue();
      final tea = await shop.addDish('Tea', price: 30);
      await queue.add(shop.store.id, draftOf(tea, qty: 2));
      await queue.add(shop.store.id, draftOf(tea, qty: 1));

      final sent = await queue.flush();

      expect(sent, 2);
      expect(queue.isEmpty, isTrue);
      final written = await shop.ordersNow();
      expect(written, hasLength(2));
      expect(written.map((o) => o.total).toList()..sort(), [30, 60]);
      // And the day's takings moved by exactly the queued amount.
      expect((await shop.dayStatsNow()).revenue, 90);
      expect((await shop.dayStatsNow()).orderCount, 2);
    });

    test('the order keeps the moment it was rung up, not the moment it sent',
        () async {
      // A lunchtime order sent at four o'clock is still a lunchtime order, and
      // every hourly report depends on that being true.
      final (shop, _, queue) = await tillWithAQueue();
      final tea = await shop.addDish('Tea', price: 30);
      final lunch = shop.atHour(12);
      await queue.add(shop.store.id, draftOf(tea, at: lunch));

      await queue.flush();

      final order = (await shop.ordersNow()).single;
      expect(order.hourOfDay, 12);
      expect((await shop.dayStatsNow()).byHour['12']?.orders, 1);
    });

    test('nothing goes while the connection is still down', () async {
      final (shop, orders, queue) = await tillWithAQueue();
      final tea = await shop.addDish('Tea', price: 30);
      await queue.add(shop.store.id, draftOf(tea));
      orders.offline = true;

      final sent = await queue.flush();

      expect(sent, 0);
      expect(queue.length, 1, reason: 'the order must stay queued, not vanish');
      expect(await shop.ordersNow(), isEmpty);
    });

    test('a half-drained queue keeps the rest', () async {
      // It stops at the first order it cannot send rather than working through
      // a row of identical failures — and what is left has to still be there.
      final (shop, orders, queue) = await tillWithAQueue();
      final tea = await shop.addDish('Tea', price: 30);
      await queue.add(shop.store.id, draftOf(tea, qty: 1));
      await queue.add(shop.store.id, draftOf(tea, qty: 2));
      orders.failAfter = 1;

      final sent = await queue.flush();

      expect(sent, 1);
      expect(queue.length, 1);
      expect((await shop.ordersNow()), hasLength(1));
    });
  });

  group('sending the same order twice', () {
    test('is harmless — it takes no second number and no second sale',
        () async {
      // A flush interrupted between the commit and the queue being cleaned up
      // sends the order again. Without the id check in `submit` that is a
      // second order number and the money counted twice.
      final (shop, orders, queue) = await tillWithAQueue();
      final tea = await shop.addDish('Tea', price: 30);
      final pending = await queue.add(shop.store.id, draftOf(tea, qty: 2));

      await queue.flush();
      // The same order, offered a second time exactly as the queue would.
      final orderNo = await orders.submit(
        store: shop.store,
        draft: pending.draft,
        createdBy: pending.createdBy,
        orderId: pending.id,
      );

      expect(await shop.ordersNow(), hasLength(1));
      expect(orderNo, 1, reason: 'the number already assigned, not a new one');
      expect((await shop.dayStatsNow()).revenue, 60);
      expect((await shop.dayStatsNow()).orderCount, 1);
    });
  });

  group('a mis-rung order', () {
    test('can be dropped without ever being sent', () async {
      final (shop, _, queue) = await tillWithAQueue();
      final tea = await shop.addDish('Tea', price: 30);
      final pending = await queue.add(shop.store.id, draftOf(tea));

      await queue.discard(pending.id);

      expect(queue.isEmpty, isTrue);
      expect(await queue.flush(), 0);
      expect(await shop.ordersNow(), isEmpty);
    });

    test('and the drop is remembered across a restart too', () async {
      final (shop, orders, queue) = await tillWithAQueue();
      final tea = await shop.addDish('Tea', price: 30);
      final pending = await queue.add(shop.store.id, draftOf(tea));
      await queue.discard(pending.id);

      final afterRestart =
          PendingOrderQueue(orders: orders, stores: shop.stores);
      orders.offline = true;
      await afterRestart.start();

      expect(afterRestart.isEmpty, isTrue);
    });
  });

  group('the bar at the top of the till', () {
    testWidgets('says nothing at all when there is nothing waiting',
        (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, const PendingOrdersBar());

      expect(find.byType(TextButton), findsNothing);
      expect(find.textContaining('waiting to be sent'), findsNothing);
    });

    testWidgets('counts what is waiting, and Send now sends it',
        (tester) async {
      // `useRepositories` rebuilds the global queue from the injected
      // repositories, so this is the app's own `pendingOrders`.
      final shop = await Shop.opened();
      final tea = await shop.addDish('Tea', price: 30);
      shop.install();
      await pendingOrders.add(shop.store.id, draftOf(tea, qty: 2));

      await showScreen(tester, const PendingOrdersBar());
      expect(find.textContaining('1 order is waiting'), findsOneWidget);

      await tester.tap(find.text('Send now'));
      await tester.pumpAndSettle();

      expect(await shop.ordersNow(), hasLength(1));
      expect((await shop.dayStatsNow()).revenue, 60);
      expect(find.textContaining('waiting to be sent'), findsNothing);
    });

    testWidgets('counts more than one properly', (tester) async {
      final shop = await Shop.opened();
      final tea = await shop.addDish('Tea', price: 30);
      shop.install();
      await pendingOrders.add(shop.store.id, draftOf(tea));
      await pendingOrders.add(shop.store.id, draftOf(tea));

      await showScreen(tester, const PendingOrdersBar());

      expect(find.textContaining('2 orders are waiting'), findsOneWidget);
    });
  });
}

/// An order repository that can be taken offline.
///
/// Extends the real one so that everything except the failure is genuine — the
/// transaction, the counter, the rollup. `unavailable` is the code Firestore
/// returns when it cannot reach the server, and it is what `describeFailure`
/// maps to [DataFailure.offline]; the queue branches on that and on nothing
/// else, so producing it exactly is the whole trick.
class _FlakyOrders extends OrderRepository {
  _FlakyOrders(Shop shop)
      : super(firestore: shop.db, auditLogs: shop.audit);

  /// Every write fails while this is set.
  bool offline = false;

  /// Or: let this many through, then fail. For a half-drained queue.
  int? failAfter;

  int _sent = 0;

  @override
  Future<int> submit({
    required Store store,
    required OrderDraft draft,
    String? createdBy,
    String? orderId,
  }) {
    if (offline || (failAfter != null && _sent >= failAfter!)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'The service is currently unavailable.',
      );
    }
    _sent++;
    return super.submit(
      store: store,
      draft: draft,
      createdBy: createdBy,
      orderId: orderId,
    );
  }
}
