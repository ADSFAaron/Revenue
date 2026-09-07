import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/models/app_user.dart';
import 'package:Revenue/models/order.dart';
import 'package:Revenue/page/addorder.dart';
import 'package:Revenue/page/analysis.dart';
import 'package:Revenue/page/transaction.dart';
import 'package:Revenue/settings/store_setting_history_order_detail.dart';
import 'package:Revenue/settings/store_staff.dart';
import 'package:Revenue/widgets/quadrant_scatter.dart';
import 'package:Revenue/widgets/stat_card.dart';

import 'shop.dart';

/// The real screens, built against a real shop.
///
/// Every other journey test stops at the data: the takings *are* zero, the
/// order *is* in the collection. This is the last step — that the figure
/// reaches the card and the order reaches the row. The gap between those two
/// is not hypothetical: a screen can read the right document and put it in the
/// wrong place, show a spinner forever because a stream was never listened to,
/// or fall back to a zero when what it actually got was an error. The last of
/// those shipped, and the comment in `transaction.dart` explaining the em dash
/// is what it left behind.
///
/// These are possible at all because the repositories in
/// `lib/database/repositories.dart` can be swapped — `shop.install()` points
/// them at the fake shop and puts them back afterwards. While they were
/// `final`, no screen in `lib/page/` or `lib/settings/` could be built by a
/// test.
void main() {
  /// The value showing on the card with this title.
  String cardValue(WidgetTester tester, String title) {
    final card = tester
        .widgetList<StatCard>(find.byType(StatCard))
        .firstWhere((c) => c.title == title);
    return card.value;
  }

  group('the till screen', () {
    testWidgets('a shop that has taken nothing shows zero, not a spinner',
        (tester) async {
      final shop = await Shop.opened(ownerName: 'Amy');
      shop.install();

      await showScreen(tester, const TransactionPage());

      expect(find.byType(StatCard), findsWidgets,
          reason: 'the cards never got past the loading state');
      expect(cardValue(tester, 'Orders'), '0');
      expect(cardValue(tester, 'Guests'), '0');
      expect(find.text('No orders yet.'), findsOneWidget);
    });

    testWidgets('and greets whoever is holding the till, by name',
        (tester) async {
      final shop = await Shop.opened(ownerName: 'Amy');
      shop.install();

      await showScreen(tester, const TransactionPage());

      expect(find.textContaining('Amy'), findsWidgets);
    });

    testWidgets('one sale later, the cards have moved', (tester) async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Beef Noodles', price: 130);
      await shop.ringUp([(dish, 2)], guestCount: 3);
      shop.install();

      await showScreen(tester, const TransactionPage());

      expect(cardValue(tester, 'Orders'), '1');
      expect(cardValue(tester, 'Guests'), '3');
      expect(cardValue(tester, 'Revenue'), contains('260'));
      expect(cardValue(tester, 'Per order'), contains('260'));
    });

    testWidgets('the order itself is on the screen, not just in the totals',
        (tester) async {
      // Two different reads — the rollup and the orders — and a screen can get
      // one right while getting the other wrong.
      final shop = await Shop.opened();
      final dish = await shop.addDish('Beef Noodles', price: 130);
      await shop.ringUp([(dish, 1)]);
      shop.install();

      await showScreen(tester, const TransactionPage());

      expect(find.text('No orders yet.'), findsNothing);
      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('several orders all reach the list', (tester) async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      final now = DateTime.now();
      for (var back = 0; back < 3; back++) {
        await shop.ringUp([(dish, 1)],
            at: now.subtract(Duration(minutes: back)));
      }
      shop.install();

      await showScreen(tester, const TransactionPage());

      expect(cardValue(tester, 'Orders'), '3');
      expect(tester.widgetList(find.byType(ListTile)).length,
          greaterThanOrEqualTo(3));
    });
  });

  group('the staff screen', () {
    testWidgets('an owner sees everybody in the shop', (tester) async {
      final shop = await Shop.opened(ownerName: 'Amy');
      final invite = await shop.staffInvite();
      await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      // Back to the owner, who is the one looking at this screen.
      await shop.signIn(email: 'owner@example.com', password: 'correct horse');
      shop.install();

      await showScreen(tester, StoreStaff(shop.store.id));

      // The tile's subtitle is two lines — the address, then the role — so
      // the address is never a Text of its own.
      expect(find.textContaining('owner@example.com'), findsOneWidget);
      expect(find.textContaining('cook@example.com'), findsOneWidget);
      expect(find.text('Amy'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);
    });

    testWidgets('including somebody who has been removed', (tester) async {
      // `active: false` is not a deletion, and the list has to keep showing
      // them — otherwise restoring somebody means finding a person who is no
      // longer anywhere on the screen.
      final shop = await Shop.opened();
      final invite = await shop.staffInvite();
      final cook = await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      await shop.users.setActive(cook.uid, false);
      await shop.signIn(email: 'owner@example.com', password: 'correct horse');
      shop.install();

      await showScreen(tester, StoreStaff(shop.store.id));

      expect(find.textContaining('cook@example.com'), findsOneWidget);
      expect(find.textContaining('No longer works here'), findsOneWidget);
    });

    testWidgets('an owner is offered the controls for a colleague',
        (tester) async {
      final shop = await Shop.opened();
      final invite = await shop.staffInvite();
      await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      await shop.signIn(email: 'owner@example.com', password: 'correct horse');
      shop.install();

      await showScreen(tester, StoreStaff(shop.store.id));

      // One menu button, on the colleague's row and not on the owner's own:
      // promoting yourself and removing yourself are the two things this
      // screen must never offer.
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, 'Invite'),
          findsOneWidget);
    });

    testWidgets('staff see the list but are offered nothing to change',
        (tester) async {
      final shop = await Shop.opened();
      final invite = await shop.staffInvite();
      await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      // The cook is left signed in — this is the screen as they see it.
      shop.install();

      await showScreen(tester, StoreStaff(shop.store.id));

      expect(find.textContaining('owner@example.com'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.widgetWithText(FloatingActionButton, 'Invite'), findsNothing,
          reason: 'staff may not issue invite codes');
    });

    testWidgets('a manager may change a colleague but not the owner',
        (tester) async {
      final shop = await Shop.opened();
      final managerInvite = await shop.staffInvite(role: UserRole.manager);
      await shop.join(
        code: managerInvite.code,
        email: 'manager@example.com',
        password: 'another one',
        displayName: 'Mia',
      );
      final staffInvite = await shop.staffInvite();
      await shop.join(
        code: staffInvite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Ben',
      );
      await shop.signIn(
          email: 'manager@example.com', password: 'another one');
      shop.install();

      await showScreen(tester, StoreStaff(shop.store.id));

      // Three people on screen, and exactly one row the manager may act on:
      // not their own, and never the owner's.
      expect(find.textContaining('owner@example.com'), findsOneWidget);
      expect(find.textContaining('manager@example.com'), findsOneWidget);
      expect(find.textContaining('cook@example.com'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });
  });

  group('the order detail screen', () {
    /// An order that reached the server at a chosen moment.
    ///
    /// Built by hand and handed straight to the screen, which takes the order
    /// as an argument. `createdAt` is a server timestamp, so there is no way
    /// to ask a Firestore — fake or real — to backdate one, and the whole
    /// point here is an order older than the correction window.
    Order placed({required Duration ago, String? by}) {
      final at = DateTime.now().subtract(ago);
      return Order(
        id: 'o1',
        orderNo: 7,
        businessDate: '2026-09-06',
        placedAt: at,
        hourOfDay: at.hour,
        weekday: at.weekday,
        items: const [
          OrderLine(itemId: 'tea', name: 'Tea', unitPrice: 30, qty: 1),
        ],
        subtotal: 30,
        total: 30,
        createdBy: by,
        createdAt: at,
      );
    }

    testWidgets('staff may correct a fresh order', (tester) async {
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
        StoreHistoryOrderDetail(shop.store.id, placed(ago: Duration.zero)),
      );

      expect(buttonEnabled(tester, 'Edit'), isTrue);
      expect(buttonEnabled(tester, 'Void'), isTrue);
    });

    testWidgets('and may not once the window has passed', (tester) async {
      // The buttons going grey is the whole client-side rule. What stops the
      // write is `firestore.rules`; this stops somebody tapping Save and being
      // answered with an error code.
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

      expect(buttonEnabled(tester, 'Edit'), isFalse);
      expect(buttonEnabled(tester, 'Void'), isFalse);
      // A pair of dead buttons with no explanation is indistinguishable from a
      // broken screen, so the screen has to say which state this is.
      expect(find.textContaining('takes a manager'), findsOneWidget);
    });

    testWidgets('an owner may correct an old order at any time',
        (tester) async {
      // The void-at-end-of-shift path.
      final shop = await Shop.opened();
      shop.install();

      await showScreen(
        tester,
        StoreHistoryOrderDetail(
          shop.store.id,
          placed(ago: const Duration(days: 2)),
        ),
      );

      expect(buttonEnabled(tester, 'Edit'), isTrue);
      expect(buttonEnabled(tester, 'Void'), isTrue);
      expect(find.textContaining('any order, at any time'), findsOneWidget);
    });

    testWidgets('an old order is still fully readable', (tester) async {
      // Viewing is never gated. It is the shop's own record.
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
          placed(ago: const Duration(days: 3)),
        ),
      );

      expect(find.textContaining('Tea'), findsWidgets);
    });
  });

  group('the add-order screen', () {
    testWidgets('offers the shop its own menu', (tester) async {
      final shop = await Shop.opened();
      await shop.addDish('Beef Noodles', price: 130);
      await shop.addDish('Braised Rice', price: 60);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));

      expect(find.textContaining('Beef Noodles'), findsWidgets);
      expect(find.textContaining('Braised Rice'), findsWidgets);
    });

    testWidgets('never offers a dish that has been retired', (tester) async {
      // A retired dish stays in the collection so past orders still read, and
      // the till is the one place it must not appear.
      final shop = await Shop.opened();
      await shop.addDish('Beef Noodles', price: 130);
      final gone = await shop.addDish('Seasonal Soup', price: 80);
      await shop.menu.deactivate(shop.store.id, gone.id);
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));

      expect(find.textContaining('Beef Noodles'), findsWidgets);
      expect(find.textContaining('Seasonal Soup'), findsNothing);
    });

    testWidgets('a shop with no menu yet says so rather than showing nothing',
        (tester) async {
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, AddOrder(shop.store.id));

      // Whatever the wording, the screen must not be blank and must not be
      // stuck on a spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Text), findsWidgets);
    });
  });

  group('the insights screen', () {
    testWidgets('a shop with real trading gets something to read',
        (tester) async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Beef Noodles', price: 200, cost: 100);
      for (var i = 0; i < 20; i++) {
        await shop.ringUp([(dish, 1)]);
      }
      shop.install();

      await showScreen(tester, const AnalysisPage());

      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'the page never finished loading');
      // The page leads with sentences rather than tables, and this shop's
      // 100-in-200 dish is half food cost — well over the watch line.
      expect(find.textContaining('Food cost'), findsOneWidget);
      expect(find.textContaining('50.0%'), findsOneWidget);

      // The Menu tab is the matrix. It plots dishes as dots against this
      // menu's own averages rather than listing them — a name only appears
      // once a dot is tapped — so what is checked here is that the chart is
      // built from this shop's figures, not that a label is present.
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      expect(find.byType(QuadrantScatter), findsOneWidget);
      expect(find.textContaining('Food cost 50.0%'), findsOneWidget);
      for (final quadrant in ['Star', 'Plowhorse', 'Puzzle', 'Dog']) {
        expect(find.text(quadrant), findsOneWidget);
      }
    });

    testWidgets('and a shop with none does not fail, it says there is none',
        (tester) async {
      // The state that made this tab look broken. An empty shop must reach a
      // finished screen, not a spinner and not an error.
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, const AnalysisPage());

      expect(find.text('Insights'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      // No trading means no food-cost finding — a percentage of nothing is
      // exactly the number this app refuses to invent.
      expect(find.textContaining('Food cost'), findsNothing);
    });
  });
}
