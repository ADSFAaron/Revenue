import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/analysis/comparison.dart';
import 'package:Revenue/analysis/menu_engineering.dart';
import 'package:Revenue/models/daily_stats.dart';

/// The window against the one before it.
///
/// Everything pinned here is about refusing to report a change that the data
/// does not support. A comparison is the easiest place in a reporting app to
/// manufacture a finding: divide by a small previous number and any shop looks
/// like it doubled.
DailyStats stats({
  int orders = 0,
  int revenue = 0,
  List<ItemStat> items = const [],
}) =>
    DailyStats(
      businessDate: '2026-08-21',
      orderCount: orders,
      revenue: revenue,
      byItem: {for (final i in items) i.itemId: i},
    );

WindowComparison compare({
  required DailyStats current,
  required DailyStats previous,
  int windowDays = 90,
  int currentTradingDays = 80,
  int previousTradingDays = 80,
}) =>
    WindowComparison(
      windowDays: windowDays,
      current: current,
      previous: previous,
      matrix: MenuEngineering.from(current),
      previousMatrix: MenuEngineering.from(previous),
      currentTradingDays: currentTradingDays,
      previousTradingDays: previousTradingDays,
    );

void main() {
  group('a change that cannot be computed is not invented', () {
    test('there is no percentage change from zero', () {
      final c = Comparison(label: 'Takings', current: 5000, previous: 0);
      expect(c.change, isNull,
          reason: 'a shop\'s first week is not "up 100%"');
    });

    test('small movement is reported as flat, not as a finding', () {
      expect(
        const Comparison(label: 'Takings', current: 10100, previous: 10000)
            .isFlat,
        isTrue,
      );
      expect(
        const Comparison(label: 'Takings', current: 12000, previous: 10000)
            .isFlat,
        isFalse,
      );
    });

    test('a rate moves in points, never in percent of a percent', () {
      // "Food cost rose 10%" from 30% is unreadable — 33% or 40%?
      const c = Comparison(
          label: 'Food cost', current: 0.33, previous: 0.30, asRate: true);
      expect(c.pointChange, closeTo(3, 1e-9));
      expect(c.isFlat, isFalse);
    });
  });

  group('whether there is anything to compare against', () {
    test('a shop with no history behind the window shows nothing', () {
      final c = compare(
        current: stats(orders: 400, revenue: 200000),
        previous: stats(),
      );
      expect(c.hasPrevious, isFalse);
    });

    test('a previous window far shorter than this one is refused', () {
      // A shop that opened six weeks into a 90-day window. "Down 60%" would be
      // describing when it opened rather than how it is trading.
      final c = compare(
        current: stats(orders: 400, revenue: 200000),
        previous: stats(orders: 40, revenue: 20000),
        currentTradingDays: 85,
        previousTradingDays: 12,
      );
      expect(c.hasPrevious, isFalse);
    });

    test('a comparable stretch is compared', () {
      final c = compare(
        current: stats(orders: 400, revenue: 200000),
        previous: stats(orders: 350, revenue: 160000),
      );
      expect(c.hasPrevious, isTrue);
      expect(c.revenue.change, closeTo(0.25, 1e-9));
      expect(c.orders.change, closeTo(50 / 350, 1e-9));
    });
  });

  group('dishes that moved', () {
    // Two dishes, both well above the placement floor. Between the windows the
    // noodles are repriced: same volume, much better margin.
    List<ItemStat> menu({required int noodleCost}) => [
          ItemStat(
              itemId: 'noodles',
              name: 'Beef Noodles',
              qty: 200,
              revenue: 40000,
              cost: noodleCost),
          const ItemStat(
              itemId: 'rice',
              name: 'Braised Rice',
              qty: 150,
              revenue: 15000,
              cost: 6000),
        ];

    test('a repricing shows up as a move between quadrants', () {
      final c = compare(
        current: stats(items: menu(noodleCost: 16000)),
        previous: stats(items: menu(noodleCost: 32000)),
      );

      final moves = c.movers;
      expect(moves, hasLength(greaterThanOrEqualTo(1)));
      final noodles = moves.firstWhere((m) => m.name == 'Beef Noodles');
      expect(noodles.from, MenuClass.plowhorse);
      expect(noodles.to, MenuClass.star);
      expect(noodles.isImprovement, isTrue);
    });

    test('a dish the matrix would not place in both windows never "moves"', () {
      // Four plates last window, forty this one. That is not a turnaround from
      // Dog to Star — it was never a Dog, it was unmeasured, and calling it a
      // turnaround would manufacture a success out of the sample size.
      final c = compare(
        current: stats(items: [
          const ItemStat(
              itemId: 'rice',
              name: 'Braised Rice',
              qty: 150,
              revenue: 15000,
              cost: 6000),
          const ItemStat(
              itemId: 'special',
              name: 'Friday Special',
              qty: 40,
              revenue: 8000,
              cost: 1000),
        ]),
        previous: stats(items: [
          const ItemStat(
              itemId: 'rice',
              name: 'Braised Rice',
              qty: 150,
              revenue: 15000,
              cost: 6000),
          const ItemStat(
              itemId: 'special',
              name: 'Friday Special',
              qty: 4,
              revenue: 800,
              cost: 700),
        ]),
      );

      expect(c.movers.any((m) => m.name == 'Friday Special'), isFalse);
    });

    test('a dish that stops selling leaves the matrix rather than becoming a '
        'Dog', () {
      final c = compare(
        current: stats(items: [
          const ItemStat(
              itemId: 'rice',
              name: 'Braised Rice',
              qty: 150,
              revenue: 15000,
              cost: 6000),
          const ItemStat(
              itemId: 'special',
              name: 'Friday Special',
              qty: 3,
              revenue: 600,
              cost: 100),
        ]),
        previous: stats(items: [
          const ItemStat(
              itemId: 'rice',
              name: 'Braised Rice',
              qty: 150,
              revenue: 15000,
              cost: 6000),
          const ItemStat(
              itemId: 'special',
              name: 'Friday Special',
              qty: 60,
              revenue: 12000,
              cost: 2000),
        ]),
      );

      expect(c.fadedOut, ['Friday Special']);
      expect(c.movers.any((m) => m.name == 'Friday Special'), isFalse);
    });
  });

  test('food cost is withheld when either window has nothing costed', () {
    final c = compare(
      current: stats(items: [
        const ItemStat(
            itemId: 'rice',
            name: 'Braised Rice',
            qty: 150,
            revenue: 15000,
            cost: 6000),
      ]),
      previous: stats(items: [
        const ItemStat(
            itemId: 'rice',
            name: 'Braised Rice',
            qty: 150,
            revenue: 15000),
      ]),
    );

    expect(c.foodCost, isNull);
  });
}
