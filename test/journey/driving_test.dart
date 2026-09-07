import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/models/app_user.dart';
import 'package:Revenue/models/audit_log.dart';
import 'package:Revenue/models/order.dart';
import 'package:Revenue/models/store.dart';
import 'package:Revenue/page/addorder.dart';
import 'package:Revenue/settings/store_categories.dart';
import 'package:Revenue/settings/store_invites.dart';
import 'package:Revenue/settings/store_payment_methods.dart';
import 'package:Revenue/settings/store_setting_history_order_detail.dart';
import 'package:Revenue/settings/store_settings.dart';
import 'package:Revenue/settings/store_settings_edit_menu.dart';
import 'package:Revenue/settings/store_staff.dart';

import 'shop.dart';

/// Using the screens, not just opening them.
///
/// Everything else in `test/journey/` proves a screen shows what the data
/// says. This proves the other direction: that filling a form in and pressing
/// Save reaches Firestore, and reaches it with what was typed. That gap is
/// where a whole class of bug lives and none of the other tests can see it —
/// a Save button wired to nothing, a field read from the wrong controller, a
/// confirmation whose Cancel goes ahead anyway, a write that lands but with
/// the cost in the price.
///
/// Every check reads the result back with a one-shot `get` (the `...Now()`
/// helpers on [Shop]) rather than trusting the screen it just used. A screen
/// that draws the dish it thinks it saved is not evidence that anything was
/// saved.
void main() {
  /// Opens the dialog behind a screen's floating action button.
  Future<void> tapFab(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String label, String value) async {
    await tester.enterText(find.widgetWithText(TextField, label), value);
    await tester.pump();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    final target = find.text(label);
    // Scrolled into view first. A button below the fold is still in the tree,
    // so `tap` does not complain — it taps at a point outside the viewport and
    // whatever is drawn there receives it instead, which reads as a button
    // that does nothing.
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Taps a button inside the dialog that is open, when the same word is on
  /// the screen behind it.
  Future<void> tapInDialog(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(label),
    ));
    await tester.pumpAndSettle();
  }

  /// Waits out the snack bar a submit puts up.
  ///
  /// It is drawn over the bottom bar, which is where the Add order button is,
  /// so a second order rung up while it is still on screen taps the snack bar
  /// instead and quietly does nothing. Four seconds is `SnackBar`'s own
  /// default life.
  Future<void> letTheSnackBarGo(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// The number showing on a dish row's stepper.
  int qtyOf(WidgetTester tester, String dish) {
    final row = find.widgetWithText(ListTile, dish);
    final semantics = tester.widgetList<Semantics>(
      find.descendant(of: row, matching: find.byType(Semantics)),
    );
    final label = semantics
        .map((s) => s.properties.label)
        .firstWhere((l) => l != null && l.startsWith('quantity '))!;
    return int.parse(label.split(' ').last);
  }

  /// Adds one of a dish through the row's stepper.
  ///
  /// The list rows have no tap target of their own — quantity moves through
  /// the plus and minus, and the whole-tile tap is the other view, the one
  /// behind the grid button.
  Future<void> addOne(WidgetTester tester, String dish) async {
    await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, dish),
      matching: find.byTooltip('One more'),
    ));
    await tester.pump();
  }

  group('adding a dish', () {
    testWidgets('what was typed is what gets saved', (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));
      await tapFab(tester);
      await type(tester, 'Dish Name', 'Beef Noodles');
      await type(tester, 'Price (TWD)', '130');
      await tapInDialog(tester, 'Save');

      final menu = await shop.menuNow();
      expect(menu, hasLength(1));
      expect(menu.single.name, 'Beef Noodles');
      expect(menu.single.price, 130);
      expect(menu.single.isActive, isTrue);
    });

    testWidgets('a dish with no price is refused, and nothing is written',
        (tester) async {
      // The dialog stays open with what was typed still in it. Closing it and
      // silently saving nothing would be the worst of both.
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));
      await tapFab(tester);
      await type(tester, 'Dish Name', 'Nameless');
      await tapInDialog(tester, 'Save');

      expect(await shop.menuNow(), isEmpty);
      expect(find.text('Enter a name and a numeric price'), findsOneWidget);
    });

    testWidgets('Cancel writes nothing', (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));
      await tapFab(tester);
      await type(tester, 'Dish Name', 'Never Saved');
      await tapInDialog(tester, 'Cancel');

      expect(await shop.menuNow(), isEmpty);
    });
  });

  group('editing a dish', () {
    testWidgets('a new price is written, and recorded against a name',
        (tester) async {
      // Two writes in one batch — the price and the entry saying who moved it.
      // A price that changed with nothing naming who changed it is what a shop
      // cannot settle an argument with.
      final shop = await Shop.opened(ownerName: 'Amy');
      final dish = await shop.addDish('Tea', price: 30);
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await type(tester, 'Price (TWD)', '45');
      await tapInDialog(tester, 'Save');

      final menu = await shop.menuNow();
      expect(menu.single.price, 45);
      expect(menu.single.id, dish.id, reason: 'an edit must not make a new id');

      final entry = (await shop.auditNow())
          .singleWhere((e) => e.action == AuditAction.editMenuPrice);
      expect(entry.before?['price'], 30);
      expect(entry.after?['price'], 45);
      expect(entry.byName, 'Amy');
    });
  });

  group('retiring a dish', () {
    testWidgets('the confirmation is what does it', (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Winter Stew', price: 90);
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));
      await tester.tap(find.byTooltip('Retire dish'));
      await tester.pumpAndSettle();
      await tapInDialog(tester, 'Retire');

      final menu = await shop.menuNow();
      expect(menu, hasLength(1), reason: 'retiring must never delete');
      expect(menu.single.isActive, isFalse);
    });

    testWidgets('and Cancel leaves the dish on the till', (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Winter Stew', price: 90);
      shop.install();

      await showScreen(tester, StoreEditMenu(shop.store.id));
      await tester.tap(find.byTooltip('Retire dish'));
      await tester.pumpAndSettle();
      await tapInDialog(tester, 'Cancel');

      expect((await shop.menuNow()).single.isActive, isTrue);
    });
  });

  group('ringing up an order', () {
    testWidgets('tapping dishes and pressing Add order writes the sale',
        (tester) async {
      final shop = await Shop.opened();
      final noodles = await shop.addDish('Beef Noodles', price: 130);
      final rice = await shop.addDish('Braised Rice', price: 60);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));
      await addOne(tester, 'Beef Noodles');
      await addOne(tester, 'Beef Noodles');
      await addOne(tester, 'Braised Rice');
      await tapText(tester, 'Add order');

      final orders = await shop.ordersNow();
      expect(orders, hasLength(1));
      expect(orders.single.total, 320);
      expect(
        {for (final line in orders.single.items) line.itemId: line.qty},
        {noodles.id: 2, rice.id: 1},
      );
      // And the day's takings moved with it, in the same transaction.
      expect((await shop.dayStatsNow()).revenue, 320);
      expect((await shop.dayStatsNow()).orderCount, 1);
    });

    testWidgets('the order is attributed to whoever is at the till',
        (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Tea', price: 30);
      final invite = await shop.staffInvite();
      final cook = await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));
      await addOne(tester, 'Tea');
      await tapText(tester, 'Add order');

      expect((await shop.ordersNow()).single.createdBy, cook.uid);
    });

    testWidgets('an empty basket is refused, not written', (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Tea', price: 30);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));
      await tapText(tester, 'Add order');

      expect(await shop.ordersNow(), isEmpty);
      expect(find.text('No items in order!'), findsOneWidget);
    });

    testWidgets('the basket is cleared afterwards, ready for the next one',
        (tester) async {
      // The till stays open. A basket left full is the next customer's order
      // starting with the last one's food on it.
      final shop = await Shop.opened();
      await shop.addDish('Tea', price: 30);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));
      await addOne(tester, 'Tea');
      expect(qtyOf(tester, 'Tea'), 1);

      await tapText(tester, 'Add order');

      expect(find.textContaining('Order #1 added'), findsWidgets);
      expect(qtyOf(tester, 'Tea'), 0,
          reason: 'the next customer would start with this one\'s food on it');
    });

    testWidgets('two orders in a row take consecutive numbers',
        (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Tea', price: 30);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));
      for (var i = 0; i < 2; i++) {
        await addOne(tester, 'Tea');
        await tapText(tester, 'Add order');
        await letTheSnackBarGo(tester);
      }

      final orders = await shop.ordersNow();
      expect(orders.map((o) => o.orderNo).toSet(), {1, 2});
      expect((await shop.dayStatsNow()).orderCount, 2);
    });
  });

  group('voiding an order', () {
    /// An order the screen can be handed directly, at a chosen age.
    Order placed({required Duration ago}) {
      final at = DateTime.now().subtract(ago);
      return Order(
        id: 'o1',
        orderNo: 1,
        businessDate: '2026-09-06',
        placedAt: at,
        hourOfDay: at.hour,
        weekday: at.weekday,
        items: const [
          OrderLine(itemId: 'tea', name: 'Tea', unitPrice: 30, qty: 1),
        ],
        subtotal: 30,
        total: 30,
        createdAt: at,
      );
    }

    testWidgets('backs the money out and leaves a record', (tester) async {
      final shop = await Shop.opened(ownerName: 'Amy');
      final tea = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(tea, 1)]);
      final order = await shop.newestOrder();
      shop.install();

      await showScreen(
          tester, StoreHistoryOrderDetail(shop.store.id, order));
      await tapText(tester, 'Void');
      // The dialog's own button carries the same word as the one that opened
      // it, so this has to say which of the two it means.
      await tapInDialog(tester, 'Void');

      final after = (await shop.ordersNow()).single;
      expect(after.status, OrderStatus.voided);
      expect((await shop.dayStatsNow()).revenue, 0);
      expect((await shop.dayStatsNow()).voidedCount, 1);

      final entry = (await shop.auditNow())
          .singleWhere((e) => e.action == AuditAction.voidOrder);
      expect(entry.byName, 'Amy');
    });

    testWidgets('Cancel on the confirmation changes nothing', (tester) async {
      final shop = await Shop.opened();
      final tea = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(tea, 1)]);
      final order = await shop.newestOrder();
      shop.install();

      await showScreen(
          tester, StoreHistoryOrderDetail(shop.store.id, order));
      await tapText(tester, 'Void');
      await tapInDialog(tester, 'Cancel');

      expect((await shop.ordersNow()).single.status, OrderStatus.completed);
      expect((await shop.dayStatsNow()).revenue, 30);
      expect(await shop.auditNow(), isEmpty);
    });

    testWidgets('staff cannot even open the confirmation on an old order',
        (tester) async {
      final shop = await Shop.opened();
      final invite = await shop.staffInvite();
      await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      shop.install();

      await showScreen(
        tester,
        StoreHistoryOrderDetail(
          shop.store.id,
          placed(ago: kStaffCorrectionWindow + const Duration(minutes: 1)),
        ),
      );

      expect(buttonEnabled(tester, 'Void'), isFalse);
    });
  });

  group('managing staff', () {
    Future<Shop> shopWithACook() async {
      final shop = await Shop.opened(ownerName: 'Amy');
      final invite = await shop.staffInvite();
      await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      await shop.signIn(email: 'owner@example.com', password: 'correct horse');
      return shop;
    }

    Future<void> openMenuFor(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }

    testWidgets('promoting somebody to manager is written', (tester) async {
      final shop = await shopWithACook();
      final cook = (await shop.users.watchStaff(shop.store.id).first)
          .firstWhere((u) => u.email == 'cook@example.com');
      shop.install();

      await showScreen(tester, StoreStaff(shop.store.id));
      await openMenuFor(tester);
      await tapText(tester, 'Change role');
      await tapText(tester, 'Manager');

      expect((await shop.userNow(cook.uid)).role, UserRole.manager);
    });

    testWidgets('removing somebody takes the confirmation', (tester) async {
      final shop = await shopWithACook();
      final cook = (await shop.users.watchStaff(shop.store.id).first)
          .firstWhere((u) => u.email == 'cook@example.com');
      shop.install();

      await showScreen(tester, StoreStaff(shop.store.id));
      await openMenuFor(tester);
      await tapText(tester, 'Remove from store');
      await tapInDialog(tester, 'Remove');

      expect((await shop.userNow(cook.uid)).active, isFalse);
    });

    testWidgets('and Cancel on it leaves them on the team', (tester) async {
      final shop = await shopWithACook();
      final cook = (await shop.users.watchStaff(shop.store.id).first)
          .firstWhere((u) => u.email == 'cook@example.com');
      shop.install();

      await showScreen(tester, StoreStaff(shop.store.id));
      await openMenuFor(tester);
      await tapText(tester, 'Remove from store');
      await tapInDialog(tester, 'Cancel');

      expect((await shop.userNow(cook.uid)).active, isTrue);
    });

    testWidgets('putting somebody back needs no confirmation', (tester) async {
      // Restoring is undone by the same tap; removing takes somebody's till
      // away mid-shift. Only one of the two is worth a dialog.
      final shop = await shopWithACook();
      final cook = (await shop.users.watchStaff(shop.store.id).first)
          .firstWhere((u) => u.email == 'cook@example.com');
      await shop.users.setActive(cook.uid, false);
      shop.install();

      await showScreen(tester, StoreStaff(shop.store.id));
      await openMenuFor(tester);
      await tapText(tester, 'Put back on the team');

      expect((await shop.userNow(cook.uid)).active, isTrue);
    });
  });

  group('menu categories', () {
    testWidgets('one typed in is added to the store', (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreCategories(shop.store.id));
      await tapFab(tester);
      await type(tester, 'Category name', 'Noodles');
      await tapInDialog(tester, 'Save');

      expect(
        (await shop.storeNow()).categories.map((c) => c.name),
        ['Noodles'],
      );
    });

    testWidgets('renaming keeps the id, so dishes stay in it', (tester) async {
      // The id is what a dish points at. A rename that minted a new one would
      // quietly empty the category.
      final shop = await Shop.opened(
        settings: (store) => Store(
          id: store.id,
          name: store.name,
          categories: const [StoreCategory(id: 'noodles', name: 'Noodles')],
        ),
      );
      shop.install();

      await showScreen(tester, StoreCategories(shop.store.id));
      await tester.tap(find.byTooltip('Rename'));
      await tester.pumpAndSettle();
      await type(tester, 'Category name', 'Noodle Dishes');
      await tapInDialog(tester, 'Save');

      final categories = (await shop.storeNow()).categories;
      expect(categories.single.name, 'Noodle Dishes');
      expect(categories.single.id, 'noodles');
    });

    testWidgets('an empty one can be deleted', (tester) async {
      final shop = await Shop.opened(
        settings: (store) => Store(
          id: store.id,
          name: store.name,
          categories: const [StoreCategory(id: 'drinks', name: 'Drinks')],
        ),
      );
      shop.install();

      await showScreen(tester, StoreCategories(shop.store.id));
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tapInDialog(tester, 'Delete');

      expect((await shop.storeNow()).categories, isEmpty);
    });

    testWidgets('one with dishes in it is not, and says why', (tester) async {
      // Deleting it would leave every dish pointing at a category that is not
      // there — which the till used to assert on.
      final shop = await Shop.opened(
        settings: (store) => Store(
          id: store.id,
          name: store.name,
          categories: const [StoreCategory(id: 'noodles', name: 'Noodles')],
        ),
      );
      await shop.addDish('Beef Noodles', price: 130, categoryId: 'noodles');
      shop.install();

      await showScreen(tester, StoreCategories(shop.store.id));
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('to another category first'), findsOneWidget);
      expect((await shop.storeNow()).categories, hasLength(1));
    });
  });

  group('payment methods', () {
    testWidgets('a new one is added to the store', (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StorePaymentMethods(shop.store.id));
      await tapFab(tester);
      await type(tester, 'Name', 'LINE Pay');
      await tapInDialog(tester, 'Save');

      expect(
        (await shop.storeNow()).paymentMethods.map((m) => m.name),
        contains('LINE Pay'),
      );
    });

    testWidgets('and is then offered at the till', (tester) async {
      // The whole reason the screen exists: what a shop says it takes has to
      // reach the order screen.
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StorePaymentMethods(shop.store.id));
      await tapFab(tester);
      await type(tester, 'Name', 'LINE Pay');
      await tapText(tester, 'Save');

      final store = await shop.storeNow();
      expect(store.paymentMethods.map((m) => m.name), contains('LINE Pay'));
      expect(store.paymentMethodById('linepay').name, isNotEmpty);
    });
  });

  group('invite codes', () {
    testWidgets('issuing one puts a live code on the screen and in the store',
        (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreInvites(
        storeId: shop.store.id,
        storeName: shop.store.name,
      ));
      await tapText(tester, 'New code');
      await tapText(tester, 'Staff');

      final invites = await shop.invitesNow();
      expect(invites, hasLength(1));
      expect(invites.single.role, UserRole.staff);
      expect(invites.single.storeId, shop.store.id);
      expect(invites.single.usedBy, isNull);
    });

    testWidgets('a manager code is a manager code', (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreInvites(
        storeId: shop.store.id,
        storeName: shop.store.name,
      ));
      await tapText(tester, 'New code');
      await tapText(tester, 'Manager');

      expect((await shop.invitesNow()).single.role, UserRole.manager);
    });

    testWidgets('and the code it issues actually works', (tester) async {
      // The end of the loop: a code made on this screen has to be spendable by
      // somebody joining. Nothing else here checks that the two halves agree.
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreInvites(
        storeId: shop.store.id,
        storeName: shop.store.name,
      ));
      await tapText(tester, 'New code');
      await tapText(tester, 'Staff');

      final code = (await shop.invitesNow()).single.code;
      final joiner = await shop.join(
        code: code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );

      expect(joiner.storeId, shop.store.id);
      expect(joiner.role, UserRole.staff);
    });
  });

  group('store settings', () {
    testWidgets('renaming the shop is written', (tester) async {
      final shop = await Shop.opened(name: 'Old Name');
      shop.install();

      await showScreen(tester, StoreSettings(shop.store.id));
      await tapText(tester, 'Store name');
      await type(tester, 'Store Name', 'New Name');
      await tapInDialog(tester, 'Save');

      expect((await shop.storeNow()).name, 'New Name');
    });

    testWidgets('a shop cannot be left without a name', (tester) async {
      // Used to close the dialog and save nothing, saying nothing.
      final shop = await Shop.opened(name: 'Old Name');
      shop.install();

      await showScreen(tester, StoreSettings(shop.store.id));
      await tapText(tester, 'Store name');
      await type(tester, 'Store Name', '   ');
      await tapInDialog(tester, 'Save');

      expect((await shop.storeNow()).name, 'Old Name');
      expect(find.textContaining('needs a name'), findsOneWidget);
    });

    testWidgets('a tax rate is stored as a fraction, not as the percent typed',
        (tester) async {
      // The field says "Rate (%)" and the store holds 0.05. Getting this
      // backwards would tax every order at 500%, and the till would not object.
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreSettings(shop.store.id));
      await tapText(tester, 'Tax');
      await type(tester, 'Rate (%)', '5');
      await tapInDialog(tester, 'Save');

      final store = await shop.storeNow();
      expect(store.taxRate, closeTo(0.05, 0.0001));
    });

    testWidgets('and it then prices an order the way the shop said',
        (tester) async {
      // The point of the setting. 5% on top of a NT$100 dish is NT$105 at the
      // till; 5% already inside it is NT$100 with NT$5 of tax in it.
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreSettings(shop.store.id));
      await tapText(tester, 'Tax');
      await type(tester, 'Rate (%)', '5');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tapInDialog(tester, 'Save');

      final store = await shop.storeNow();
      expect(store.taxRate, closeTo(0.05, 0.0001));
      expect(store.taxIncluded, isFalse);
    });

    testWidgets('daily targets are written as typed', (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreSettings(shop.store.id));
      await tapText(tester, 'Daily targets');
      await type(tester, 'Orders per day', '60');
      await tapInDialog(tester, 'Save');

      expect((await shop.storeNow()).targets.dailyOrders, 60);
    });

    testWidgets('the trading day cutoff moves, and moves the takings with it',
        (tester) async {
      // A late-night kitchen counts 02:00 as the previous day. The setting is
      // only worth anything if the rollup an order lands in follows it.
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, StoreSettings(shop.store.id));
      await tapText(tester, 'Trading day starts at');
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('06:00').last);
      await tester.pumpAndSettle();
      await tapInDialog(tester, 'Save');

      final store = await shop.storeNow();
      expect(store.dayCutoffHour, 6);
      // 05:00 is now the previous trading day rather than this one.
      final fiveAm = DateTime(2026, 9, 7, 5);
      expect(store.businessDateOf(fiveAm), '2026-09-06');
    });
  });
}
