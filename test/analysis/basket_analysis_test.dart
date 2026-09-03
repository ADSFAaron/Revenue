import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/analysis/basket_analysis.dart';
import 'package:Revenue/models/order.dart';

Order orderWith(List<String> itemIds,
        {OrderStatus status = OrderStatus.completed}) =>
    Order(
      id: itemIds.join('-'),
      orderNo: 1,
      businessDate: '2026-08-21',
      placedAt: DateTime(2026, 8, 21, 12),
      hourOfDay: 12,
      weekday: 5,
      status: status,
      items: [
        for (final id in itemIds)
          OrderLine(itemId: id, name: id, unitPrice: 100, qty: 1),
      ],
    );

void main() {
  test('finds a genuine pairing and states its confidence', () {
    final orders = [
      for (var i = 0; i < 8; i++) orderWith(['noodles', 'egg']),
      for (var i = 0; i < 4; i++) orderWith(['noodles']),
      for (var i = 0; i < 10; i++) orderWith(['rice']),
    ];

    final analysis = BasketAnalysis.from(orders);
    final rule = analysis.rules.firstWhere(
        (r) => r.antecedentId == 'noodles' && r.consequentId == 'egg');

    expect(rule.together, 8);
    expect(rule.antecedentCount, 12);
    expect(rule.confidence, closeTo(8 / 12, 0.0001));
    expect(rule.lift, greaterThan(1));
  });

  test('lift discards a drink that comes with everything', () {
    // Tea is in every single order, so it tells you nothing about any dish.
    final orders = [
      for (var i = 0; i < 20; i++) orderWith(['noodles', 'tea']),
      for (var i = 0; i < 20; i++) orderWith(['rice', 'tea']),
    ];

    final analysis = BasketAnalysis.from(orders);
    // Confidence for noodles -> tea is a perfect 100%, which is exactly the
    // trap; lift is 1.0 and the rule must not be reported.
    expect(
      analysis.rules.where((r) => r.consequentId == 'tea'),
      isEmpty,
    );
  });

  test('voided orders and single-item orders are handled', () {
    final orders = [
      for (var i = 0; i < 6; i++) orderWith(['a', 'b']),
      for (var i = 0; i < 6; i++)
        orderWith(['a', 'b'], status: OrderStatus.voided),
      // Enough unrelated tickets that b is not simply what this shop sells.
      // Without them the pairing is real but unprovable at six observations,
      // and the significance test correctly declines to report it — which
      // would leave this test with no rule to inspect.
      for (var i = 0; i < 20; i++) orderWith(['c']),
    ];

    final analysis = BasketAnalysis.from(orders);
    expect(analysis.basketCount, 26); // 6 completed pairs + 20 singles
    expect(analysis.multiItemBasketCount, 6);
    final rule = analysis.rules.firstWhere((r) => r.antecedentId == 'a');
    expect(rule.together, 6); // the voided six did not count
  });

  test('a pairing that only just beats chance is not reported at small n', () {
    // 4 of 5 anchovy orders also took bread — 80% against a 70% base rate, so
    // lift is 1.14 and the flat `lift >= 1.05` cut this replaced would have
    // printed "80% of anchovy orders also include bread" from five tickets.
    final orders = [
      for (var i = 0; i < 4; i++) orderWith(['anchovy', 'bread']),
      orderWith(['anchovy', 'olives']),
      for (var i = 0; i < 66; i++) orderWith(['bread', 'olives']),
      for (var i = 0; i < 29; i++) orderWith(['olives']),
    ];

    final analysis = BasketAnalysis.from(orders);
    final claim = analysis.rules
        .where((r) => r.antecedentId == 'anchovy' && r.consequentId == 'bread');
    expect(claim, isEmpty);

    // The point estimate really is above the base rate. What is missing is the
    // evidence, and that is the distinction the old cut could not draw.
    expect(BasketAnalysis.wilsonLowerBound(4, 5), lessThan(0.70));
  });

  test('the same rate with real evidence behind it is reported', () {
    // Identical 80% against the same 70% base rate, seen 400 times instead of
    // five. This is the pair the previous test has to be distinguished from,
    // or the fix would just be a stricter threshold.
    final orders = [
      for (var i = 0; i < 400; i++) orderWith(['anchovy', 'bread']),
      for (var i = 0; i < 100; i++) orderWith(['anchovy', 'olives']),
      for (var i = 0; i < 300; i++) orderWith(['bread', 'olives']),
      for (var i = 0; i < 200; i++) orderWith(['olives']),
    ];

    final analysis = BasketAnalysis.from(orders);
    final rule = analysis.rules.firstWhere(
        (r) => r.antecedentId == 'anchovy' && r.consequentId == 'bread');
    expect(rule.confidence, closeTo(0.80, 0.001));
    expect(rule.confidenceLowerBound, greaterThan(0.70));
    // The cautious end sits below the point estimate, which is the whole idea.
    expect(rule.confidenceLowerBound, lessThan(rule.confidence));
  });

  test('a rare pairing is below the reporting threshold', () {
    final orders = [
      for (var i = 0; i < 2; i++) orderWith(['a', 'b']),
      for (var i = 0; i < 50; i++) orderWith(['c']),
    ];
    expect(BasketAnalysis.from(orders).isEmpty, isTrue);
  });
}
