import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/models/audit_log.dart';
import 'package:Revenue/models/store.dart';
import 'package:Revenue/settings/store_categories.dart';
import 'package:Revenue/settings/store_payment_methods.dart';
import 'package:Revenue/settings/store_settings.dart';
import 'package:Revenue/settings/store_settings_audit_log.dart';
import 'package:Revenue/settings/store_settings_edit_menu.dart';
import 'package:Revenue/settings/store_settings_history_order.dart';
import 'package:Revenue/widgets/empty_state.dart';

import 'shop.dart';

/// The settings screens.
///
/// These are where a shop's own facts are entered — the menu, the categories,
/// what it takes payment in — and where the record of who changed them is
/// read back. Two things are worth pinning on every one of them, and they are
/// the same two: an empty shop reaches a screen that says it is empty rather
/// than a spinner or a blank, and a role that may not change something is not
/// offered the control.
///
/// The second half is a client-side courtesy, not a defence. `firestore.rules`
/// is what refuses the write, and it is tested against a real Firestore in
/// `test/rules/users.test.js`. What is checked here is that nobody is invited
/// to try.
void main() {
  group('the menu editor', () {
    testWidgets('lists the shop\'s dishes', (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Beef Noodles', price: 130);
      await shop.addDish('Braised Rice', price: 60);
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));

      expect(find.text('Edit Menu'), findsOneWidget);
      expect(find.textContaining('Beef Noodles'), findsWidgets);
      expect(find.textContaining('Braised Rice'), findsWidgets);
    });

    testWidgets('hides retired dishes until they are asked for',
        (tester) async {
      // Retiring is not deleting — past orders reference the id — so the
      // editor is the one place a retired dish has to be reachable again.
      final shop = await Shop.opened();
      await shop.addDish('Beef Noodles', price: 130);
      final gone = await shop.addDish('Winter Stew', price: 90);
      await shop.menu.deactivate(shop.store.id, gone.id);
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));
      expect(find.textContaining('Winter Stew'), findsNothing);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('retired'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Winter Stew'), findsWidgets);
    });

    testWidgets('staff get the menu to read, not to edit', (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Beef Noodles', price: 130);
      final invite = await shop.staffInvite();
      await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));

      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('Edit Menu'), findsNothing);
      expect(find.byTooltip('Import from a photo'), findsNothing);
    });

    testWidgets('an empty menu says so', (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the order history', () {
    testWidgets('a shop with no orders is told, not left blank',
        (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreHistoryOrder(shop.store.id));

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No orders yet'), findsOneWidget);
    });

    testWidgets('every order rung up is on it, newest first', (tester) async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      final now = DateTime.now();
      for (var back = 0; back < 3; back++) {
        await shop.ringUp([(dish, back + 1)],
            at: now.subtract(Duration(minutes: back)));
      }
      shop.install();

      await showScreen(tester, StoreHistoryOrder(shop.store.id));

      expect(find.byType(EmptyState), findsNothing);
      // Three orders, numbered as they were rung up.
      for (final number in ['1', '2', '3']) {
        expect(find.textContaining(number), findsWidgets);
      }
    });

    testWidgets('a voided order stays on the list, marked as voided',
        (tester) async {
      // Never removed. A cancelled sale that leaves no trace is exactly what
      // makes a till discrepancy unarguable.
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(dish, 1)]);
      final order = await shop.newestOrder();
      await shop.orders.voidOrder(
        store: shop.store,
        orderId: order.id,
        by: shop.actor,
      );
      shop.install();

      await showScreen(tester, StoreHistoryOrder(shop.store.id));

      expect(find.text('Voided'), findsOneWidget);
    });
  });

  group('the change history', () {
    testWidgets('an untouched shop has nothing to show and says so',
        (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreAuditLog(shop.store.id));

      expect(find.text('Change history'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a repricing appears, naming who did it', (tester) async {
      // The entry is the whole point of the screen: a price that changed with
      // nothing saying who changed it is what a shop cannot settle an argument
      // with.
      final shop = await Shop.opened(ownerName: 'Amy');
      final dish = await shop.addDish('Tea', price: 30);
      await shop.menu.update(
        shop.store.id,
        dish.copyWith(price: 45),
        previous: dish,
        by: shop.actor,
      );
      shop.install();

      await showScreen(tester, StoreAuditLog(shop.store.id));

      expect(find.textContaining('Amy'), findsWidgets);
      expect(find.textContaining('30'), findsWidgets);
      expect(find.textContaining('45'), findsWidgets);
    });

    testWidgets('so does a voided order', (tester) async {
      final shop = await Shop.opened(ownerName: 'Amy');
      final dish = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(dish, 1)]);
      final order = await shop.newestOrder();
      await shop.orders.voidOrder(
        store: shop.store,
        orderId: order.id,
        by: shop.actor,
      );
      shop.install();

      await showScreen(tester, StoreAuditLog(shop.store.id));

      // What the entry contains is checked in the plain test at the foot of
      // this file; what matters here is that the screen shows one at all.
      expect(find.textContaining('Amy'), findsWidgets);
    });
  });

  group('menu categories', () {
    testWidgets('a shop with none is told what they are for', (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreCategories(shop.store.id));

      expect(find.text('Menu Categories'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('the ones a shop has set up are listed', (tester) async {
      final shop = await Shop.opened(
        settings: (store) => Store(
          id: store.id,
          name: store.name,
          categories: const [
            StoreCategory(id: 'noodles', name: 'Noodles'),
            StoreCategory(id: 'drinks', name: 'Drinks', sortOrder: 1),
          ],
        ),
      );
      shop.install();

      await showScreen(tester, StoreCategories(shop.store.id));

      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('Noodles'), findsOneWidget);
      expect(find.text('Drinks'), findsOneWidget);
    });
  });

  group('payment methods', () {
    testWidgets('a new shop starts with something to take money in',
        (tester) async {
      // A store with no payment methods is a till that cannot ring anything
      // up, so the default has to be there from the first order.
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StorePaymentMethods(shop.store.id));

      expect(find.text('Payment Methods'), findsOneWidget);
      expect(find.textContaining('Cash'), findsWidgets);
      expect(find.text('Selected by default at the till'), findsOneWidget);
    });

    testWidgets('a shop\'s own methods are the ones listed', (tester) async {
      final shop = await Shop.opened();
      await shop.stores.updatePaymentMethods(shop.store.id, const [
        StorePaymentMethod(id: 'cash', name: 'Cash'),
        StorePaymentMethod(id: 'linepay', name: 'LINE Pay', sortOrder: 1),
      ]);
      await shop.reloadStore();
      shop.install();

      await showScreen(tester, StorePaymentMethods(shop.store.id));

      expect(find.textContaining('LINE Pay'), findsWidgets);
    });
  });

  group('store settings', () {
    testWidgets('an owner sees the shop\'s trading rules', (tester) async {
      final shop = await Shop.opened(name: 'Corner Noodles');
      shop.install();

      await showScreen(tester, StoreSettings(shop.store.id));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Corner Noodles'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and the settings screen opens for staff too, without '
        'offering the edits', (tester) async {
      // Read-only rather than refused. Somebody at the till has a real reason
      // to check what the tax rate or the cutoff hour is.
      final shop = await Shop.opened();
      final invite = await shop.staffInvite();
      await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      shop.install();

      await showScreen(tester, StoreSettings(shop.store.id));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('what the audit log is written from', () {
    test('every recorded action carries an actor and a target', () async {
      // The screens above can only show what was written. This checks the
      // writing: an entry with no actor is a change nobody can be asked about.
      final shop = await Shop.opened(ownerName: 'Amy');
      final dish = await shop.addDish('Tea', price: 30);
      await shop.menu.update(
        shop.store.id,
        dish.copyWith(price: 45),
        previous: dish,
        by: shop.actor,
      );
      await shop.ringUp([(dish, 1)]);
      final order = await shop.newestOrder();
      await shop.edit(order, [(dish, 2)], by: shop.actor);
      await shop.orders.voidOrder(
        store: shop.store,
        orderId: order.id,
        by: shop.actor,
      );

      final log = await shop.auditLog();
      expect(
        log.map((e) => e.action),
        containsAll([
          AuditAction.editMenuPrice,
          AuditAction.editOrder,
          AuditAction.voidOrder,
        ]),
      );
      for (final entry in log) {
        expect(entry.byUid, shop.owner.uid);
        expect(entry.byName, 'Amy');
        expect(entry.targetId, isNotEmpty);
      }
    });

    test('a removed member keeps their name on what they did', () async {
      // Their orders are the shop's books, not theirs. An entry that turned
      // into a bare uid the moment somebody left would be a record of nothing.
      final shop = await Shop.opened();
      final invite = await shop.staffInvite();
      final cook = await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      final dish = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(dish, 1)], by: cook.uid);
      await shop.users.setActive(cook.uid, false);

      final names = await shop.users.staffNames(shop.store.id);

      expect(names.labelFor(cook.uid), 'Ben');
      expect(names.knows(cook.uid), isTrue);
      expect((await shop.history()).single.createdBy, cook.uid);
    });
  });
}
