import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/analysis/menu_engineering.dart';
import 'package:Revenue/models/order.dart';
import 'package:Revenue/settings/user_manual.dart';

/// A manual that quietly disagrees with the app is worse than no manual: it
/// is the one place a person goes when they already suspect a number, and it
/// gets believed.
///
/// So the two figures it quotes are read from the constants that enforce them
/// — `kStaffCorrectionWindow`, which greys out the edit buttons, and
/// `MenuEngineering.foodCostWarningRate`, which raises the flag on Insights —
/// and these tests fail if either is ever restated as a literal.
void main() {
  Future<void> open(WidgetTester tester, ManualTopic topic) async {
    // Tall enough that an expanded chapter is laid out rather than clipped.
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: UserManual(initialTopic: topic)));
    await tester.pumpAndSettle();
  }

  testWidgets('the correction window is quoted from the constant',
      (tester) async {
    await open(tester, ManualTopic.till);

    final minutes = kStaffCorrectionWindow.inMinutes;
    expect(find.textContaining('$minutes minutes'), findsWidgets);
  });

  testWidgets('the food cost warning line is quoted from the constant',
      (tester) async {
    await open(tester, ManualTopic.insights);

    final percent = (MenuEngineering.foodCostWarningRate * 100).round();
    expect(find.textContaining('Above $percent%'), findsOneWidget);
  });

  testWidgets('it opens on the chapter it was asked for', (tester) async {
    await open(tester, ManualTopic.insights);

    // The Insights help button lands on the four classes, not on the top of a
    // manual somebody then has to search.
    expect(find.textContaining('Plowhorse'), findsWidgets);
    // And the chapters nobody asked for stay shut.
    expect(find.textContaining('Put the menu in'), findsNothing);
  });

  testWidgets('scrolling a chapter out of view and back does not throw',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UserManual()));

    final list = find.byType(ListView);

    // Two chapters touched, so that the list disagrees with whatever a tile
    // might have remembered on its own.
    await tester.tap(find.text(ManualTopic.setup.title));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(ManualTopic.money.title), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text(ManualTopic.money.title));
    await tester.pumpAndSettle();

    // Far enough that the first chapter is disposed, then back, which builds
    // it again. A tile that restored its own expansion here would report the
    // change mid-build and bring the manual down.
    await tester.fling(list, const Offset(0, -4000), 3000);
    await tester.pumpAndSettle();
    await tester.fling(list, const Offset(0, 6000), 3000);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(ManualTopic.setup.title), findsOneWidget);
  });

  testWidgets('opening a chapter shuts the one before it', (tester) async {
    await open(tester, ManualTopic.setup);
    expect(find.textContaining('Put the menu in'), findsOneWidget);

    await tester.tap(find.text(ManualTopic.roles.title));
    await tester.pumpAndSettle();

    expect(find.textContaining('Put the menu in'), findsNothing);
  });

  testWidgets('every chapter has a body', (tester) async {
    for (final topic in ManualTopic.values) {
      await open(tester, topic);
      expect(find.text(topic.title), findsOneWidget);
    }
  });

  // Somebody who turns the system font up is exactly the person who opens a
  // manual, so every chapter is laid out at the sizes they actually use, on a
  // narrow phone, and the numbered step badges have to grow with their
  // numerals rather than clip them.
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('chapters lay out at a ${scale}x text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final topic in ManualTopic.values) {
        await tester.pumpWidget(MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: MaterialApp(home: UserManual(initialTopic: topic)),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: topic.name);
      }
    });
  }
}
