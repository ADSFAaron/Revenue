import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/models/store.dart';
import 'package:Revenue/page/addorder.dart';
import 'package:Revenue/settings/store_categories.dart';
import 'package:Revenue/settings/store_payment_methods.dart';
import 'package:Revenue/settings/store_settings_edit_menu.dart';

import 'shop.dart';

/// The two things a shop arranges by hand: the order the till shows dishes in,
/// and which of the two tills it shows them on.
///
/// Both are easy to dismiss as decoration and neither is. The order a menu is
/// in is the order somebody's hand goes to at speed, and a drag that appears
/// to work but writes nothing is a rearrangement that comes back on the next
/// device. The grid is the layout the counter actually runs on — a separate
/// widget from the list, with its own tap target and its own way of taking a
/// dish back off, and until now nothing built it at all.
void main() {
  group('the big-button till', () {
    /// Swaps the order screen from the list to the grid.
    Future<void> useBigButtons(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Show as big buttons'));
      await tester.pumpAndSettle();
    }

    testWidgets('the whole tile adds one, not just an icon on it',
        (tester) async {
      // The reason the grid exists: at a counter the target is the tile, about
      // 150x140, rather than the 24pt plus a list row offers.
      final shop = await Shop.opened();
      final noodles = await shop.addDish('Beef Noodles', price: 130);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));
      await useBigButtons(tester);

      await tester.tap(find.text('Beef Noodles'));
      await tester.pump();
      await tester.tap(find.text('Beef Noodles'));
      await tester.pump();
      await tester.tap(find.text('Add order'));
      await tester.pumpAndSettle();

      final order = (await shop.ordersNow()).single;
      expect(order.items.single.itemId, noodles.id);
      expect(order.items.single.qty, 2);
      expect(order.total, 260);
    });

    testWidgets('the minus in the corner appears only once there is one to '
        'take away', (tester) async {
      // An untouched tile has exactly one thing you can do to it.
      final shop = await Shop.opened();
      await shop.addDish('Tea', price: 30);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));
      await useBigButtons(tester);

      expect(find.byTooltip('One fewer Tea'), findsNothing);

      await tester.tap(find.text('Tea'));
      await tester.pump();

      expect(find.byTooltip('One fewer Tea'), findsOneWidget);
    });

    testWidgets('and it takes the dish back off', (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Tea', price: 30);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));
      await useBigButtons(tester);
      await tester.tap(find.text('Tea'));
      await tester.pump();
      await tester.tap(find.text('Tea'));
      await tester.pump();

      await tester.tap(find.byTooltip('One fewer Tea'));
      await tester.pump();
      await tester.tap(find.text('Add order'));
      await tester.pumpAndSettle();

      expect((await shop.ordersNow()).single.items.single.qty, 1);
    });

    testWidgets('taking the last one off empties the basket', (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Tea', price: 30);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));
      await useBigButtons(tester);
      await tester.tap(find.text('Tea'));
      await tester.pump();
      await tester.tap(find.byTooltip('One fewer Tea'));
      await tester.pump();

      await tester.tap(find.text('Add order'));
      await tester.pumpAndSettle();

      expect(await shop.ordersNow(), isEmpty);
      expect(find.text('No items in order!'), findsOneWidget);
    });

    testWidgets('the grid shows the shop\'s own menu and nothing retired',
        (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Beef Noodles', price: 130);
      final gone = await shop.addDish('Seasonal Soup', price: 80);
      await shop.menu.deactivate(shop.store.id, gone.id);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));
      await useBigButtons(tester);

      expect(find.text('Beef Noodles'), findsOneWidget);
      expect(find.text('Seasonal Soup'), findsNothing);
    });

    testWidgets('and switching back to the list keeps what is in the basket',
        (tester) async {
      // The two layouts are one order. Losing the basket on a layout change
      // would be a rung-up order thrown away by a stray tap.
      final shop = await Shop.opened();
      await shop.addDish('Tea', price: 30);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));
      await useBigButtons(tester);
      await tester.tap(find.text('Tea'));
      await tester.pump();
      await tester.tap(find.text('Tea'));
      await tester.pump();

      await tester.tap(find.byTooltip('Show as a list'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add order'));
      await tester.pumpAndSettle();

      expect((await shop.ordersNow()).single.items.single.qty, 2);
    });
  });

  group('dragging the menu into a new order', () {
    /// Drags the row carrying [label] far enough to move it one place down.
    ///
    /// A `ReorderableListView` starts its drag from a long press on the item
    /// itself; there is no separate handle on these rows.
    Future<void> dragDown(WidgetTester tester, String label) async {
      final gesture =
          await tester.startGesture(tester.getCenter(find.text(label)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      // In steps, because a reorderable list decides where an item lands from
      // where the pointer is as it moves, not from where it is dropped.
      for (var step = 0; step < 8; step++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('writes the new order, so another device sees it too',
        (tester) async {
      // `sortOrder` is what the till reads. A drag that only moved the widget
      // would come back in the old order on the next cold start.
      final shop = await Shop.opened();
      final first = await shop.addDish('First', sortOrder: 0);
      final second = await shop.addDish('Second', sortOrder: 1);
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));
      await dragDown(tester, 'First');

      final menu = await shop.menuNow();
      final order = {for (final item in menu) item.name: item.sortOrder};
      expect(order['Second']! < order['First']!, isTrue,
          reason: 'the drag did not reach Firestore');
      expect(menu.map((i) => i.id).toSet(), {first.id, second.id},
          reason: 'reordering must not mint new dishes');
    });

    testWidgets('and the till then offers them in that order', (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('First', sortOrder: 0);
      await shop.addDish('Second', sortOrder: 1);
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));
      await dragDown(tester, 'First');

      final onTill = await shop.menu.fetchActive(shop.store.id);
      expect(onTill.map((i) => i.name), ['Second', 'First']);
    });

    testWidgets('a filtered menu is not draggable at all', (tester) async {
      // Dragging inside a filtered view would write an order derived from a
      // subset back over the whole menu.
      final shop = await Shop.opened();
      await shop.addDish('Beef Noodles', sortOrder: 0);
      await shop.addDish('Braised Rice', sortOrder: 1);
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));
      expect(find.byType(ReorderableListView), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Beef');
      await tester.pumpAndSettle();

      expect(find.byType(ReorderableListView), findsNothing);
    });

    testWidgets('and neither is one a staff account is looking at',
        (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Beef Noodles', sortOrder: 0);
      await shop.addDish('Braised Rice', sortOrder: 1);
      final invite = await shop.staffInvite();
      await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));

      expect(find.byType(ReorderableListView), findsNothing);
    });
  });

  group('dragging the categories and payment methods', () {
    Future<void> dragDown(WidgetTester tester, Finder handle) async {
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      for (var step = 0; step < 8; step++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('a category dragged down is written in its new place',
        (tester) async {
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
      await dragDown(tester, find.text('Noodles'));

      expect(
        (await shop.storeNow()).categories.map((c) => c.id),
        ['drinks', 'noodles'],
      );
    });

    testWidgets('and so is a payment method', (tester) async {
      // The first one in the list is what a new order starts on, so this is
      // not cosmetic: dragging changes what every till defaults to.
      final shop = await Shop.opened();
      await shop.stores.updatePaymentMethods(shop.store.id, const [
        StorePaymentMethod(id: 'cash', name: 'Cash'),
        StorePaymentMethod(id: 'linepay', name: 'LINE Pay', sortOrder: 1),
      ]);
      await shop.reloadStore();
      shop.install();

      await showScreen(tester, StorePaymentMethods(shop.store.id));
      await dragDown(tester, find.text('Cash'));

      final store = await shop.storeNow();
      expect(store.paymentMethods.map((m) => m.id), ['linepay', 'cash']);
      expect(store.defaultPaymentMethodId, 'linepay');
    });
  });
}
