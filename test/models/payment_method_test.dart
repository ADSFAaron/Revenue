import 'package:flutter_test/flutter_test.dart';

import 'package:Revenue/models/order.dart';
import 'package:Revenue/models/store.dart';
import 'package:Revenue/widgets/payment_icons.dart';

/// Payment methods moved from a hard-coded `enum` onto the store document, so
/// a shop can name what it actually takes. The risk that came with the move is
/// history: an order carries only the id, and the old `PaymentMethod.fromId`
/// answered every id it did not recognise with `cash` — which would quietly
/// move a deleted method's takings into the cash column.
void main() {
  const store = Store(id: 's', name: 'Shop');

  test('a store with nothing stored still has methods to ring up against', () {
    expect(store.paymentMethods, isNotEmpty);
    expect(store.defaultPaymentMethodId, 'cash');
  });

  test('the built-in ids match what past orders already carry', () {
    expect(
      kDefaultPaymentMethods.map((m) => m.id),
      containsAll(<String>['cash', 'credit_card', 'line_pay', 'other']),
      reason: 'Changing a default id orphans every order that stored it.',
    );
  });

  test('a deleted method keeps its own name rather than becoming cash', () {
    const shop = Store(
      id: 's',
      name: 'Shop',
      paymentMethods: [StorePaymentMethod(id: 'cash', name: '現金')],
    );

    final resolved = shop.paymentMethodById('line_pay');
    expect(resolved.id, 'line_pay');
    expect(resolved.name, isNot('現金'));
  });

  test('an id nobody has ever heard of is readable, not raw', () {
    expect(resolvePaymentMethod(kDefaultPaymentMethods, 'store_credit').name,
        'Store credit');
  });

  test('an order with no payment field on it reads as the default', () {
    final order = Order.fromMap('o1', const {});
    expect(order.paymentMethodId, kDefaultPaymentMethodId);
  });

  test('every default names an icon that survives tree-shaking', () {
    for (final method in kDefaultPaymentMethods) {
      expect(resolvePaymentIcon(method.iconKey).key, method.iconKey,
          reason: '${method.name} points at an icon key that does not exist');
    }
  });
}
