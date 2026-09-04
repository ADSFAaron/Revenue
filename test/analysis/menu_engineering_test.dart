import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/analysis/menu_engineering.dart';
import 'package:Revenue/models/daily_stats.dart';

DailyStats statsWith(List<ItemStat> items) => DailyStats(
      businessDate: '2026-08-21',
      orderCount: 100,
      byItem: {for (final i in items) i.itemId: i},
    );

void main() {
  test('separates the plowhorse from the star', () {
    final analysis = MenuEngineering.from(statsWith([
      // Sells hugely, 20% margin — tops any best-seller chart, earns little.
      const ItemStat(
          itemId: 'noodles',
          name: 'Beef Noodles',
          qty: 200,
          revenue: 40000,
          cost: 32000),
      // Sells well, 60% margin.
      const ItemStat(
          itemId: 'rice',
          name: 'Braised Rice',
          qty: 150,
          revenue: 15000,
          cost: 6000),
      // Sells quietly, high margin. Above the placement floor on purpose —
      // at the 5 units this used to carry, the matrix now declines to judge
      // it, which is the whole point of `minimumUnits`.
      const ItemStat(
          itemId: 'tea', name: 'Oolong', qty: 12, revenue: 1200, cost: 240),
      // Sells quietly, thin margin.
      const ItemStat(
          itemId: 'soup', name: 'Corn Soup', qty: 11, revenue: 550, cost: 495),
    ]));

    MenuClass classOf(String id) =>
        analysis.items.firstWhere((i) => i.stat.itemId == id).menuClass;

    expect(classOf('noodles'), MenuClass.plowhorse);
    expect(classOf('rice'), MenuClass.star);
    expect(classOf('tea'), MenuClass.puzzle);
    expect(classOf('soup'), MenuClass.dog);
  });

  group('too few sold', () {
    test('a dish under the floor is withheld rather than judged', () {
      final analysis = MenuEngineering.from(statsWith([
        const ItemStat(
            itemId: 'rice',
            name: 'Braised Rice',
            qty: 150,
            revenue: 15000,
            cost: 6000),
        // Four plates. Which quadrant this lands in is decided by whichever
        // table happened to order it, and "consider dropping it" is not a
        // sentence worth printing on that.
        const ItemStat(
            itemId: 'special',
            name: 'Friday Special',
            qty: 4,
            revenue: 800,
            cost: 700),
      ]));

      expect(analysis.items.map((i) => i.stat.itemId), ['rice']);
      expect(analysis.insufficient.map((i) => i.itemId), ['special']);
      expect(analysis.unclassified, isEmpty,
          reason: 'it is costed — the problem is volume, not a missing cost');
    });

    test('withholding a verdict does not move any figure', () {
      // The thin dish is still a real sale. Dropping it from the totals would
      // inflate every other dish's share of units and shift the average margin
      // they are all measured against, so a dish nobody ordered would silently
      // reclassify the ones they did.
      const rice = ItemStat(
          itemId: 'rice',
          name: 'Braised Rice',
          qty: 150,
          revenue: 15000,
          cost: 6000);
      const thin = ItemStat(
          itemId: 'special',
          name: 'Friday Special',
          qty: 4,
          revenue: 800,
          cost: 700);

      final withThin = MenuEngineering.from(statsWith([rice, thin]));

      expect(withThin.totalRevenue, 15800);
      expect(withThin.totalCost, 6700);
      expect(withThin.foodCostRate, closeTo(6700 / 15800, 1e-9));
    });

    test('exactly at the floor is placed', () {
      final analysis = MenuEngineering.from(statsWith([
        ItemStat(
            itemId: 'edge',
            name: 'On The Line',
            qty: MenuEngineering.minimumUnits,
            revenue: 1000,
            cost: 400),
      ]));

      expect(analysis.items, hasLength(1));
      expect(analysis.insufficient, isEmpty);
    });
  });

  test('a dish with no cost is excluded, never crowned a star', () {
    final analysis = MenuEngineering.from(statsWith([
      const ItemStat(
          itemId: 'uncosted',
          name: 'Mystery Dish',
          qty: 500,
          revenue: 50000,
          cost: 0),
      const ItemStat(
          itemId: 'rice',
          name: 'Braised Rice',
          qty: 10,
          revenue: 1000,
          cost: 400),
    ]));

    expect(
        analysis.items.map((i) => i.stat.itemId), isNot(contains('uncosted')));
    expect(analysis.unclassified.map((i) => i.itemId), contains('uncosted'));
    // The uncosted dish must not drag the food cost rate down either.
    expect(analysis.totalRevenue, 1000);
    expect(analysis.foodCostRate, closeTo(0.4, 0.0001));
  });

  test('food cost warning line', () {
    final high = MenuEngineering.from(statsWith([
      const ItemStat(itemId: 'a', name: 'A', qty: 10, revenue: 1000, cost: 400),
    ]));
    expect(high.foodCostIsHigh, isTrue);

    final ok = MenuEngineering.from(statsWith([
      const ItemStat(itemId: 'a', name: 'A', qty: 10, revenue: 1000, cost: 250),
    ]));
    expect(ok.foodCostIsHigh, isFalse);
  });

  test('an empty menu produces an empty matrix rather than a crash', () {
    final analysis = MenuEngineering.from(statsWith([]));
    expect(analysis.isEmpty, isTrue);
    expect(analysis.foodCostRate, isNull);
  });

  group('revenue coverage', () {
    test('is the costed share of takings, not of the dish count', () {
      final analysis = MenuEngineering.from(statsWith([
        // One costed dish carrying most of the money.
        const ItemStat(
            itemId: 'noodles',
            name: 'Beef Noodles',
            qty: 100,
            revenue: 9000,
            cost: 3000),
        // Two uncosted dishes, more of them but a small share of takings.
        const ItemStat(
            itemId: 'tea', name: 'Oolong', qty: 40, revenue: 600, cost: 0),
        const ItemStat(
            itemId: 'egg', name: 'Tea Egg', qty: 30, revenue: 400, cost: 0),
      ]));

      // Two thirds of the menu is uncosted and yet 90% of the money is
      // accounted for — which is the case the old "covers only the dishes with
      // costs on file" wording could not tell from its opposite.
      expect(analysis.unclassified, hasLength(2));
      expect(analysis.revenueCoverage, closeTo(0.90, 0.001));
      expect(analysis.coverageIsLow, isFalse);
    });

    test('flags a menu where the costed dishes are the minority of takings',
        () {
      final analysis = MenuEngineering.from(statsWith([
        const ItemStat(
            itemId: 'tea', name: 'Oolong', qty: 10, revenue: 1000, cost: 400),
        const ItemStat(
            itemId: 'set', name: 'Lunch Set', qty: 50, revenue: 9000, cost: 0),
      ]));

      expect(analysis.revenueCoverage, closeTo(0.10, 0.001));
      expect(analysis.coverageIsLow, isTrue);
    });

    test('nothing costed is 0% covered rather than an absent number', () {
      final analysis = MenuEngineering.from(statsWith([
        const ItemStat(
            itemId: 'set', name: 'Lunch Set', qty: 50, revenue: 9000, cost: 0),
      ]));

      expect(analysis.items, isEmpty);
      expect(analysis.revenueCoverage, 0);
      expect(analysis.coverageIsLow, isTrue);
    });

    test('an empty period has no coverage to report', () {
      final analysis = MenuEngineering.from(statsWith(const []));
      expect(analysis.revenueCoverage, isNull);
      expect(analysis.coverageIsLow, isFalse);
    });
  });
}
