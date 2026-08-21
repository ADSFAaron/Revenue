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
      const ItemStat(itemId: 'noodles', name: 'Beef Noodles', qty: 200, revenue: 40000, cost: 32000),
      // Sells well, 60% margin.
      const ItemStat(itemId: 'rice', name: 'Braised Rice', qty: 150, revenue: 15000, cost: 6000),
      // Barely sells, high margin.
      const ItemStat(itemId: 'tea', name: 'Oolong', qty: 5, revenue: 500, cost: 100),
      // Barely sells, low margin.
      const ItemStat(itemId: 'soup', name: 'Corn Soup', qty: 4, revenue: 200, cost: 180),
    ]));

    MenuClass classOf(String id) =>
        analysis.items.firstWhere((i) => i.stat.itemId == id).menuClass;

    expect(classOf('noodles'), MenuClass.plowhorse);
    expect(classOf('rice'), MenuClass.star);
    expect(classOf('tea'), MenuClass.puzzle);
    expect(classOf('soup'), MenuClass.dog);
  });

  test('a dish with no cost is excluded, never crowned a star', () {
    final analysis = MenuEngineering.from(statsWith([
      const ItemStat(itemId: 'uncosted', name: 'Mystery Dish', qty: 500, revenue: 50000, cost: 0),
      const ItemStat(itemId: 'rice', name: 'Braised Rice', qty: 10, revenue: 1000, cost: 400),
    ]));

    expect(analysis.items.map((i) => i.stat.itemId), isNot(contains('uncosted')));
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
}
