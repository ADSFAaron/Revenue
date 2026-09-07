import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/models/order.dart';

import 'shop.dart';

/// Ringing up, and finding it again afterwards.
///
/// The join this covers is the one a counter notices first and no unit test
/// can see: an order that writes without error and then is not in the history.
/// `submit` returning a number proves a transaction committed, not that
/// anything can read what it wrote — those are different collections, a
/// different query and a different sort.
void main() {
  test('an order reaches the history, with what was sold on it', () async {
    final shop = await Shop.opened();
    final noodles = await shop.addDish('Beef Noodles', price: 130);
    final rice = await shop.addDish('Braised Rice', price: 60);

    final orderNo = await shop.ringUp([(noodles, 2), (rice, 1)]);

    final history = await shop.history();
    expect(history, hasLength(1), reason: 'the order is not in the history');

    final order = history.single;
    expect(order.orderNo, orderNo);
    expect(order.total, 320);
    expect(order.items.map((i) => (i.name, i.qty)), [
      ('Beef Noodles', 2),
      ('Braised Rice', 1),
    ]);
    expect(order.status, OrderStatus.completed);
  });

  test('order numbers count up within a trading day', () async {
    final shop = await Shop.opened();
    final dish = await shop.addDish('Tea', price: 30);

    expect(await shop.ringUp([(dish, 1)]), 1);
    expect(await shop.ringUp([(dish, 1)]), 2);
    expect(await shop.ringUp([(dish, 1)]), 3);
  });

  test('the history is newest first', () async {
    final shop = await Shop.opened();
    final dish = await shop.addDish('Tea', price: 30);
    final now = DateTime.now();

    await shop.ringUp([(dish, 1)], at: now.subtract(const Duration(hours: 2)));
    await shop.ringUp([(dish, 2)], at: now.subtract(const Duration(hours: 1)));
    await shop.ringUp([(dish, 3)], at: now);

    final history = await shop.history();
    expect(history.map((o) => o.items.single.qty), [3, 2, 1]);
  });

  test('an order carries who rang it up', () async {
    final shop = await Shop.opened();
    final dish = await shop.addDish('Tea', price: 30);

    await shop.ringUp([(dish, 1)]);

    expect((await shop.history()).single.createdBy, shop.owner.uid);
  });
}
