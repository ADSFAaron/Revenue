import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/models/audit_log.dart';

import 'shop.dart';

/// Putting the shop's own dishes on the till, and changing them afterwards.
///
/// The menu is the one collection the rest of the app reads through: an order
/// line copies a dish's name, price and cost at the moment of sale, and the
/// analytics group by its id. So the thing worth pinning is not that `add`
/// writes a document — it is which reads see the result, and what happens to
/// the orders that already referenced a dish when somebody changes it.
void main() {
  group('adding', () {
    test('a new dish is on the till straight away', () async {
      final shop = await Shop.opened();

      await shop.addDish('Beef Noodles', price: 130);

      final onTill = await shop.menu.fetchActive(shop.store.id);
      expect(onTill.map((i) => i.name), ['Beef Noodles']);
      expect(onTill.single.price, 130);
      expect(onTill.single.isActive, isTrue);
    });

    test('dishes come back in the order the shop arranged them', () async {
      // `sortOrder`, not insertion order and not alphabetical. The menu editor
      // is a drag-to-reorder list and the till has to agree with it.
      final shop = await Shop.opened();
      await shop.addDish('Third', sortOrder: 2);
      await shop.addDish('First', sortOrder: 0);
      await shop.addDish('Second', sortOrder: 1);

      final onTill = await shop.menu.fetchActive(shop.store.id);
      expect(onTill.map((i) => i.name), ['First', 'Second', 'Third']);
    });
  });

  group('editing', () {
    test('a rename and a new price are both read back', () async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Beef Noodle', price: 130);

      await shop.menu.update(
        shop.store.id,
        dish.copyWith(name: 'Beef Noodles (Large)', price: 150),
        previous: dish,
        by: Actor(uid: shop.owner.uid, name: shop.owner.displayName),
      );

      final onTill = await shop.menu.fetchActive(shop.store.id);
      expect(onTill.single.name, 'Beef Noodles (Large)');
      expect(onTill.single.price, 150);
    });

    test('a repricing leaves an audit entry naming who did it', () async {
      // The entry is the point. A price that changed with nothing saying who
      // changed it is the one thing a shop cannot settle an argument with.
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);

      await shop.menu.update(
        shop.store.id,
        dish.copyWith(price: 35),
        previous: dish,
        by: Actor(uid: shop.owner.uid, name: 'Owner'),
      );

      final log = await shop.auditLog();
      final entry = log.singleWhere((e) => e.action == AuditAction.editMenuPrice);
      expect(entry.targetId, dish.id);
      expect(entry.before?['price'], 30);
      expect(entry.after?['price'], 35);
      expect(entry.byName, 'Owner');
    });

    test('a rename alone is not worth an audit entry', () async {
      // Deliberate: logging every keystroke buries the entries that matter.
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);

      await shop.menu.update(
        shop.store.id,
        dish.copyWith(name: 'Green Tea'),
        previous: dish,
        by: Actor(uid: shop.owner.uid, name: 'Owner'),
      );

      expect(await shop.auditLog(), isEmpty);
    });

    test('a new price does not rewrite what was already sold', () async {
      // An order line carries the price at the moment of sale. If a repricing
      // reached back through the history, every past total would move and the
      // books would stop agreeing with the till roll.
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(dish, 2)]);

      await shop.menu.update(
        shop.store.id,
        dish.copyWith(price: 50),
        previous: dish,
      );

      final order = (await shop.history()).single;
      expect(order.items.single.unitPrice, 30);
      expect(order.total, 60);
      expect((await shop.dayStats()).revenue, 60);
    });
  });

  group('deleting', () {
    test('a retired dish leaves the till but stays on the record', () async {
      // Never a real delete: past orders reference this id, and a missing item
      // turns them into rows nobody can interpret.
      final shop = await Shop.opened();
      final dish = await shop.addDish('Seasonal Soup', price: 80);
      await shop.ringUp([(dish, 1)]);

      await shop.menu.deactivate(shop.store.id, dish.id);

      expect(await shop.menu.fetchActive(shop.store.id), isEmpty);
      expect(await shop.menu.fetchAll(shop.store.id), hasLength(1));
    });

    test('and the order that sold it still reads correctly', () async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Seasonal Soup', price: 80);
      await shop.ringUp([(dish, 1)]);

      await shop.menu.deactivate(shop.store.id, dish.id);

      final order = (await shop.history()).single;
      expect(order.items.single.name, 'Seasonal Soup');
      expect(order.total, 80);
      expect((await shop.dayStats()).byItem[dish.id]?.qty, 1);
    });

    test('a retired dish can be brought back', () async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Winter Stew', price: 90);
      await shop.menu.deactivate(shop.store.id, dish.id);

      await shop.menu.reactivate(shop.store.id, dish.id);

      expect(await shop.menu.fetchActive(shop.store.id), hasLength(1));
    });
  });

  test('the menu editor sees retired dishes, the till does not', () async {
    // Two different reads, and the difference is the whole reason both exist.
    final shop = await Shop.opened();
    final keep = await shop.addDish('Rice', sortOrder: 0);
    final retire = await shop.addDish('Soup', sortOrder: 1);
    await shop.menu.deactivate(shop.store.id, retire.id);

    expect(
      (await shop.menu.watchAll(shop.store.id).first).map((i) => i.id),
      [keep.id, retire.id],
    );
    expect(
      (await shop.menu.fetchActive(shop.store.id)).map((i) => i.id),
      [keep.id],
    );
  });
}
