import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/analysis/demand_profile.dart';
import 'package:Revenue/analysis/headline.dart';
import 'package:Revenue/analysis/menu_engineering.dart';
import 'package:Revenue/models/order.dart';

import 'shop.dart';

/// From the till to the reports.
///
/// Every figure on Analytics and Insights is read from `dailyStats`, never
/// from the orders themselves — a month is thirty document reads that way
/// instead of a few thousand. The price of that is a rollup written by the
/// same transaction as the order, and a rollup is a second copy of the truth.
/// Second copies drift. What is checked here is that the reports and the
/// orders are still saying the same thing after the sorts of things a shop
/// does to them.
void main() {
  group("today's takings", () {
    test('add up to what was actually rung up', () async {
      final shop = await Shop.opened();
      final noodles = await shop.addDish('Beef Noodles', price: 130);
      final rice = await shop.addDish('Braised Rice', price: 60);

      await shop.ringUp([(noodles, 2), (rice, 1)], guestCount: 2);
      await shop.ringUp([(rice, 3)], guestCount: 1);

      final today = await shop.dayStats();
      expect(today.orderCount, 2);
      expect(today.guestCount, 3);
      expect(today.revenue, 320 + 180);

      // And the same number, arrived at the long way round.
      final fromOrders = (await shop.history())
          .fold<int>(0, (sum, order) => sum + order.total);
      expect(today.revenue, fromOrders);
    });

    test('break down by dish, and the dishes add up to the total', () async {
      final shop = await Shop.opened();
      final noodles = await shop.addDish('Beef Noodles', price: 130);
      final rice = await shop.addDish('Braised Rice', price: 60);

      await shop.ringUp([(noodles, 2), (rice, 1)]);
      await shop.ringUp([(noodles, 1)]);

      final byItem = (await shop.dayStats()).byItem;
      expect(byItem[noodles.id]?.qty, 3);
      expect(byItem[noodles.id]?.revenue, 390);
      expect(byItem[rice.id]?.qty, 1);
      expect(
        byItem.values.fold<int>(0, (sum, item) => sum + item.revenue),
        (await shop.dayStats()).revenue,
      );
    });

    test('break down by payment method', () async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      final methods = shop.store.paymentMethods.map((m) => m.id).toList();

      await shop.ringUp([(dish, 1)], paymentMethodId: methods.first);
      await shop.ringUp([(dish, 2)], paymentMethodId: methods.first);

      final byPayment = (await shop.dayStats()).byPayment;
      expect(byPayment[methods.first]?.orders, 2);
      expect(byPayment[methods.first]?.revenue, 90);
    });

    test('break down by channel', () async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);

      await shop.ringUp([(dish, 1)]);
      await shop.ringUp([(dish, 1)], channel: OrderChannel.takeout);

      final byChannel = (await shop.dayStats()).byChannel;
      expect(byChannel[OrderChannel.dineIn.id]?.orders, 1);
      expect(byChannel[OrderChannel.takeout.id]?.orders, 1);
    });

    test('a voided order leaves the totals but is counted as voided',
        () async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(dish, 1)]);
      await shop.ringUp([(dish, 2)]);

      final newest = (await shop.history()).first;
      await shop.orders.voidOrder(
        store: shop.store,
        orderId: newest.id,
        by: shop.actor,
      );

      final today = await shop.dayStats();
      expect(today.revenue, 30);
      expect(today.orderCount, 1);
      expect(today.voidedCount, 1);
      // The order is still there to look at. It is the money that left.
      expect(await shop.history(), hasLength(2));
    });
  });

  group('a range of days', () {
    test('reads back only the days asked for, oldest first', () async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      final today = DateTime.now();

      for (var back = 0; back < 4; back++) {
        await shop.ringUp(
          [(dish, back + 1)],
          at: today.subtract(Duration(days: back)),
        );
      }

      final from = shop.store.businessDateOf(
        today.subtract(const Duration(days: 2)),
      );
      final to = shop.store.businessDateOf(today);

      final days = await shop.stats.fetchRange(
        shop.store.id,
        fromBusinessDate: from,
        toBusinessDate: to,
      );

      expect(days, hasLength(3));
      expect(days.map((d) => d.businessDate), isA<Iterable<String>>());
      expect(
        days.map((d) => d.businessDate).toList(),
        List.of(days.map((d) => d.businessDate))..sort(),
        reason: 'the range must come back oldest first',
      );
      expect(days.map((d) => d.revenue), [90, 60, 30]);
    });

    test('a day with no trading is simply absent, not a zero row', () async {
      // Only days with takings exist as documents. The reports have to cope
      // with a range shorter than the number of dates in it — a Monday the
      // shop was shut is not a Monday that took nothing.
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      final today = DateTime.now();

      await shop.ringUp([(dish, 1)], at: today);
      await shop.ringUp([(dish, 1)], at: today.subtract(const Duration(days: 2)));

      final days = await shop.stats.fetchRange(
        shop.store.id,
        fromBusinessDate:
            shop.store.businessDateOf(today.subtract(const Duration(days: 3))),
        toBusinessDate: shop.store.businessDateOf(today),
      );

      expect(days, hasLength(2));
    });
  });

  group('Insights', () {
    test('the matrix sorts a shop\'s own dishes, from its own orders',
        () async {
      // The whole chain: dishes with costs on them, orders against those
      // dishes, a rollup written by those orders, a matrix built off that
      // rollup. Nothing here is hand-fed.
      final shop = await Shop.opened();
      final star = await shop.addDish('Beef Noodles', price: 200, cost: 40);
      final dog = await shop.addDish('Cold Side', price: 60, cost: 45);

      for (var i = 0; i < 30; i++) {
        await shop.ringUp([(star, 1)]);
      }
      for (var i = 0; i < 12; i++) {
        await shop.ringUp([(dog, 1)]);
      }

      final matrix = MenuEngineering.from(await shop.dayStats());
      final classes = {
        for (final item in matrix.items) item.name: item.menuClass,
      };

      expect(classes['Beef Noodles'], MenuClass.star);
      expect(classes['Cold Side'], MenuClass.dog);
    });

    test('a dish with no cost is withheld rather than counted as free',
        () async {
      // The rule the whole app runs on: an unknown number is shown as unknown.
      // Counting an uncosted dish at zero cost would make it the most
      // profitable thing on the menu.
      final shop = await Shop.opened();
      final costed = await shop.addDish('Noodles', price: 200, cost: 40);
      final uncosted = await shop.addDish('Special', price: 200);

      for (var i = 0; i < 12; i++) {
        await shop.ringUp([(costed, 1)]);
        await shop.ringUp([(uncosted, 1)]);
      }

      final matrix = MenuEngineering.from(await shop.dayStats());

      expect(matrix.items.map((i) => i.name), isNot(contains('Special')));
      expect(matrix.unclassified.map((i) => i.name), contains('Special'));
      expect(matrix.uncostedRevenue, 2400);
    });

    test('a dish nobody has bought enough of is held back, not classified',
        () async {
      final shop = await Shop.opened();
      final thin = await shop.addDish('Rare Special', price: 200, cost: 40);

      await shop.ringUp([(thin, MenuEngineering.minimumUnits - 1)]);

      final matrix = MenuEngineering.from(await shop.dayStats());

      expect(matrix.items, isEmpty);
      expect(matrix.insufficient.map((i) => i.name), ['Rare Special']);
    });

    test('the busy-times profile finds the hour the shop was busy', () async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      final noon = shop.atHour(12);

      for (var i = 0; i < 5; i++) {
        await shop.ringUp([(dish, 1)], at: noon);
      }
      await shop.ringUp([(dish, 1)], at: shop.atHour(20));

      final profile = DemandProfile.from(
        [await shop.dayStats()],
        dayCutoffHour: shop.store.dayCutoffHour,
      );

      expect(profile.peak?.hour, 12);
      expect(profile.activeHours, containsAll([12, 20]));
    });

    test('the headlines are sentences about this shop, and they carry numbers',
        () async {
      // Insights leads with these. A page that opens on an empty list is the
      // state that made the tab look broken, so what is pinned is that a shop
      // with real trading behind it gets something to read.
      final shop = await Shop.opened();
      final dish = await shop.addDish('Beef Noodles', price: 200, cost: 100);
      for (var i = 0; i < 20; i++) {
        await shop.ringUp([(dish, 1)]);
      }

      final stats = await shop.dayStats();
      final headlines = headlinesFrom(
        matrix: MenuEngineering.from(stats),
        demand: DemandProfile.from([stats],
            dayCutoffHour: shop.store.dayCutoffHour),
        windowDays: 1,
      );

      expect(headlines, isNotEmpty);
      for (final headline in headlines) {
        expect(headline.title, isNotEmpty);
        expect(headline.detail, isNotEmpty);
      }
      // 100/200 is a 50% food cost, well over the warning line, so the menu
      // must be one of the things it has something to say about.
      expect(headlines.map((h) => h.topic), contains(HeadlineTopic.menu));
      expect(
        headlines.map((h) => h.severity),
        contains(HeadlineSeverity.warning),
      );
    });

    test('a shop with nothing behind it gets no headlines rather than wrong '
        'ones', () async {
      final shop = await Shop.opened();
      final stats = await shop.dayStats();

      final headlines = headlinesFrom(
        matrix: MenuEngineering.from(stats),
        demand: DemandProfile.from([stats]),
        windowDays: 1,
      );

      // Whatever it produces, it must not invent a finding out of no data.
      for (final headline in headlines) {
        expect(headline.title, isNot(contains('null')));
        expect(headline.title, isNot(contains('NaN')));
      }
    });
  });

  test('an edit moves the analytics with it', () async {
    // The join that ties this whole file together: correcting an order has to
    // move every figure the reports read, not just the order itself.
    final shop = await Shop.opened();
    final cheap = await shop.addDish('Tea', price: 30);
    final dear = await shop.addDish('Noodles', price: 130);
    await shop.ringUp([(cheap, 1)]);

    final order = (await shop.history()).single;
    await shop.edit(order, [(dear, 1)]);

    final today = await shop.dayStats();
    expect(today.revenue, 130);
    expect(today.orderCount, 1);
    expect(today.byItem[cheap.id]?.qty ?? 0, 0);
    expect(today.byItem[dear.id]?.qty, 1);
  });
}
