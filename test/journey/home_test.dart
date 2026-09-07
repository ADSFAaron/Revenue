import 'package:flutter_test/flutter_test.dart';

import 'shop.dart';

/// What the way-in screen reads before anybody has done anything.
///
/// The distinction that matters here is between *zero* and *nothing*. A shop
/// that has taken no money today should read NT$0 — a real figure, and the
/// right one. What it must not do is read blank, or fail, or show the last
/// shop's number, because all three are indistinguishable to somebody standing
/// at a counter wondering whether the till is working.
///
/// So both states are pinned: an empty shop reads zero everywhere, and one
/// order later every one of those figures has moved.
void main() {
  group('a shop that has taken nothing', () {
    test('reads zero, not blank and not an error', () async {
      final shop = await Shop.opened();

      final today = await shop.dayStats();
      expect(today.revenue, 0);
      expect(today.orderCount, 0);
      expect(today.guestCount, 0);
      expect(today.isEmpty, isTrue);
    });

    test('has an empty history rather than a failed one', () async {
      final shop = await Shop.opened();

      expect(await shop.history(), isEmpty);
    });

    test('and lifetime totals of zero across zero trading days', () async {
      // The caption under the store name. `fetchTotals` is an aggregation
      // query, which answers nothing at all when there are no documents — the
      // figures have to come back as zero rather than as null on the screen.
      final shop = await Shop.opened();

      final totals = await shop.stats.fetchTotals(shop.store.id);
      expect(totals.revenue, 0);
      expect(totals.orderCount, 0);
      expect(totals.days, 0);
      expect(totals.averageOrderValue, 0);
    });
  });

  group('after one sale', () {
    test('today reads the sale', () async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Beef Noodles', price: 130);

      await shop.ringUp([(dish, 2)], guestCount: 2);

      final today = await shop.dayStats();
      expect(today.revenue, 260);
      expect(today.orderCount, 1);
      expect(today.guestCount, 2);
      expect(today.isEmpty, isFalse);
    });

    test('and so do the lifetime totals', () async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Beef Noodles', price: 130);
      await shop.ringUp([(dish, 2)]);

      final totals = await shop.stats.fetchTotals(shop.store.id);
      expect(totals.revenue, 260);
      expect(totals.orderCount, 1);
      expect(totals.days, 1);
      expect(totals.averageOrderValue, 260);
    });

    test('yesterday is still zero — a day is a day', () async {
      // The rollup is keyed by trading day. A total that leaked across the
      // boundary would make every past day drift upwards as the shop traded.
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(dish, 1)]);

      final yesterday = await shop.dayStats(
        shop.store.businessDateOf(
          DateTime.now().subtract(const Duration(days: 1)),
        ),
      );
      expect(yesterday.revenue, 0);
      expect(yesterday.isEmpty, isTrue);
    });
  });

  test('the figures follow the shop, not the device', () async {
    // Two shops on one machine. A total read from the wrong store is the kind
    // of thing that looks like an accounting error for weeks.
    final first = await Shop.opened(name: 'First', email: 'a@example.com');
    final second = await Shop.opened(name: 'Second', email: 'b@example.com');

    final dish = await first.addDish('Tea', price: 30);
    await first.ringUp([(dish, 3)]);

    expect((await first.dayStats()).revenue, 90);
    expect((await second.dayStats()).revenue, 0);
  });
}
