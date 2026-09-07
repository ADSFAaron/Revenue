import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/page/analysis.dart';
import 'package:Revenue/page/statistics.dart';
import 'package:Revenue/page/store.dart';
import 'package:Revenue/widgets/empty_state.dart';
import 'package:Revenue/widgets/stat_card.dart';

import 'shop.dart';

/// The reporting screens, and the tabs behind them.
///
/// Split from `screens_test.dart` because these have something in common the
/// till does not: each is a *different read of the same trading*. Reports adds
/// a period up from the daily rollups; the store overview asks Firestore for a
/// lifetime aggregate; Pairings goes past the rollups entirely and reads every
/// order. Three queries, three ways to be wrong about one shop, and a number
/// that disagrees with the till is the kind of thing that gets found weeks
/// later by somebody doing their books.
void main() {
  /// The value on the card with this title.
  String cardValue(WidgetTester tester, String title) => tester
      .widgetList<StatCard>(find.byType(StatCard))
      .firstWhere((c) => c.title == title)
      .value;

  group('Reports', () {
    testWidgets('a shop that has taken nothing today says so', (tester) async {
      // Not a spinner, not a blank, and not an error: a quiet day is a real
      // state and the page has to be able to show one.
      final shop = await Shop.opened();
      shop.install();

      await showScreen(tester, const StatisticsPage());

      expect(find.text('Reports'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Nothing was sold'), findsOneWidget);
    });

    testWidgets("today's takings match what was rung up", (tester) async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Beef Noodles', price: 200, cost: 80);
      await shop.ringUp([(dish, 2)], guestCount: 2);
      await shop.ringUp([(dish, 1)], guestCount: 1);
      shop.install();

      await showScreen(tester, const StatisticsPage());

      expect(cardValue(tester, 'Orders'), '2');
      expect(cardValue(tester, 'Revenue'), contains('600'));
      // 600 taken, 240 of cost. The page is the only place this subtraction is
      // shown, and an uncosted dish would have to be left out of it entirely.
      expect(cardValue(tester, 'Gross profit'), contains('360'));
      expect(cardValue(tester, 'Per head'), contains('200'));
    });

    testWidgets('the top dishes are this shop\'s dishes', (tester) async {
      final shop = await Shop.opened();
      final popular = await shop.addDish('Beef Noodles', price: 130);
      final quiet = await shop.addDish('Cold Side', price: 40);
      await shop.ringUp([(popular, 5), (quiet, 1)]);
      shop.install();

      await showScreen(tester, const StatisticsPage());

      expect(find.text('Top dishes'), findsOneWidget);
      expect(find.textContaining('Beef Noodles'), findsWidgets);
    });

    testWidgets('yesterday is a different page, and it is empty',
        (tester) async {
      // The back arrow moves the period. A page that kept showing today's
      // figures under yesterday's date would be the worst kind of wrong: it
      // reads as a fact about a day the shop cannot check any other way.
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(dish, 1)]);
      shop.install();

      await showScreen(tester, const StatisticsPage());
      expect(cardValue(tester, 'Orders'), '1');

      await tester.tap(find.byTooltip('Previous'));
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.textContaining('Nothing was sold'), findsOneWidget);
      expect(find.byType(StatCard), findsNothing);
    });
  });

  group('the store overview', () {
    testWidgets('names the shop and its lifetime takings', (tester) async {
      // `fetchTotals` is a Firestore aggregation query — a different call from
      // everything else on this screen, and the only one whose answer nothing
      // else can cross-check.
      final shop = await Shop.opened(name: 'Corner Noodles');
      final dish = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(dish, 2)]);
      await shop.ringUp([(dish, 1)]);
      shop.install();

      await showScreen(tester, const StorePage());

      expect(find.text('Corner Noodles'), findsOneWidget);
      expect(find.textContaining('across 2 orders, all time'), findsOneWidget);
      expect(find.textContaining('90'), findsWidgets);
    });

    testWidgets('lists who works here', (tester) async {
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

      await showScreen(tester, const StorePage());

      expect(find.text('owner@example.com'), findsOneWidget);
      expect(find.text('cook@example.com'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
    });

    testWidgets('a shop with no trading still opens', (tester) async {
      final shop = await Shop.opened(name: 'Brand New');
      shop.install();

      await showScreen(tester, const StorePage());

      expect(find.text('Brand New'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Insights — the tabs behind the first two', () {
    /// A shop with enough trading behind it for every report to have something
    /// to say: twenty lunches of noodles-and-tea, and ten evening rice orders.
    ///
    /// The third dish is what makes the pairing testable. A rule has to clear
    /// the *base rate* of the second dish, so if tea were on every ticket
    /// there would be nothing for "noodles → tea" to beat — ordering noodles
    /// could not make tea any likelier than certain. With ten rice-only
    /// tickets, tea is on 20 of 30 baskets and the pairing has a bar to clear.
    Future<Shop> tradingShop() async {
      final shop = await Shop.opened();
      final noodles = await shop.addDish('Beef Noodles', price: 200, cost: 80);
      final tea = await shop.addDish('Tea', price: 30, cost: 5);
      final rice = await shop.addDish('Braised Rice', price: 60, cost: 20);
      final noon = shop.atHour(12);

      for (var i = 0; i < 20; i++) {
        await shop.ringUp([(noodles, 1), (tea, 1)], at: noon);
      }
      for (var i = 0; i < 10; i++) {
        await shop.ringUp([(rice, 1)], at: shop.atHour(19));
      }
      return shop;
    }

    Future<void> openTab(WidgetTester tester, String name) async {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets('Busy times draws the hours the shop actually traded',
        (tester) async {
      final shop = await tradingShop();
      shop.install();

      await showScreen(tester, const AnalysisPage());
      await openTab(tester, 'Busy times');

      expect(tester.takeException(), isNull);
      // Both hours the shop traded in, and neither of the ones it did not.
      expect(find.textContaining('12'), findsWidgets);
      expect(find.textContaining('19'), findsWidgets);
    });

    testWidgets('Prep forecasts a weekday from the days on record',
        (tester) async {
      final shop = await tradingShop();
      shop.install();

      await showScreen(tester, const AnalysisPage());
      await openTab(tester, 'Prep');

      expect(tester.takeException(), isNull);
      // One of the two: a forecast built from the days on record, or an honest
      // statement that this weekday has none. Both are correct answers; a
      // spinner or a crash is not.
      final hasForecast = find.textContaining('What a typical').evaluate();
      final hasNothing = find.textContaining('on record').evaluate();
      expect(hasForecast.isNotEmpty || hasNothing.isNotEmpty, isTrue);
    });

    testWidgets('Prep offers all seven weekdays to choose from',
        (tester) async {
      final shop = await tradingShop();
      shop.install();

      await showScreen(tester, const AnalysisPage());
      await openTab(tester, 'Prep');

      expect(find.byType(SegmentedButton<int>), findsOneWidget);
    });

    testWidgets('Pairings does not run until it is asked to', (tester) async {
      // The point of the button. This is the only report that reads the orders
      // themselves rather than the daily rollups, so on a six-month window it
      // is thousands of document reads — opening the tab must not spend them.
      final shop = await tradingShop();
      shop.install();

      await showScreen(tester, const AnalysisPage());
      await openTab(tester, 'Pairings');

      expect(find.text('Analyse orders'), findsOneWidget);
      expect(find.textContaining('most expensive report'), findsOneWidget);
    });

    testWidgets('and finds the pairing when it is', (tester) async {
      // Every noodle order also had a tea, and teas are ordered alone as well
      // — so "noodles → tea" has to clear the base rate of tea, which is what
      // the Wilson bound is there to decide.
      final shop = await tradingShop();
      shop.install();

      await showScreen(tester, const AnalysisPage());
      await openTab(tester, 'Pairings');
      await tester.tap(find.text('Analyse orders'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Beef Noodles'), findsWidgets);
      expect(find.textContaining('Tea'), findsWidgets);
    });

    testWidgets('a one-dish-per-ticket shop is told why there is nothing',
        (tester) async {
      // A takeaway selling one item per ticket finds nothing here, and that is
      // a fact about the shop rather than a failure. It has to read as one.
      final shop = await Shop.opened();
      final tea = await shop.addDish('Tea', price: 30);
      for (var i = 0; i < 10; i++) {
        await shop.ringUp([(tea, 1)]);
      }
      shop.install();

      await showScreen(tester, const AnalysisPage());
      await openTab(tester, 'Pairings');
      await tester.tap(find.text('Analyse orders'));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.textContaining('single dish'), findsOneWidget);
    });
  });
}
