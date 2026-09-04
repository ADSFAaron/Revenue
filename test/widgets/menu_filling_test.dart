import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/theme.dart';
import 'package:Revenue/widgets/menu_filling.dart';

Widget harness({bool dark = false, bool still = false}) => MaterialApp(
      theme: dark
          ? MaterialTheme(const TextTheme()).dark()
          : MaterialTheme(const TextTheme()).light(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: const Scaffold(
          body: Center(child: SizedBox(height: 160, child: MenuFilling())),
        ),
      ),
    );

void main() {
  testWidgets('it keeps running without settling', (tester) async {
    // A repeating animation never settles, and `pumpAndSettle` anywhere near it
    // would hang the suite. This is the guard that it is a loop and not a
    // one-shot somebody later reaches for pumpAndSettle on.
    await tester.pumpWidget(harness());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
    expect(find.byType(MenuFilling), findsOneWidget);
  });

  testWidgets('it draws in both palettes', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(harness(dark: dark));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reduced motion shows the finished menu, not an empty card',
      (tester) async {
    // The point of the picture is what a full menu looks like. Holding still
    // must not mean holding it at frame zero, which is a blank card.
    await tester.pumpWidget(harness(still: true));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final painter = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(MenuFilling),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(painter.painter, isNotNull);
    // No ticker to leave running.
    expect(tester.binding.transientCallbackCount, 0);
  });
}
