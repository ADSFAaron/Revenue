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
      orderWith(['c']),
    ];

    final analysis = BasketAnalysis.from(orders);
    expect(analysis.basketCount, 7); // 6 completed pairs + 1 single
    expect(analysis.multiItemBasketCount, 6);
    final rule = analysis.rules.firstWhere((r) => r.antecedentId == 'a');
    expect(rule.together, 6); // the voided six did not count
  });

  test('a rare pairing is below the reporting threshold', () {
    final orders = [
      for (var i = 0; i < 2; i++) orderWith(['a', 'b']),
      for (var i = 0; i < 50; i++) orderWith(['c']),
    ];
    expect(BasketAnalysis.from(orders).isEmpty, isTrue);
  });
}
