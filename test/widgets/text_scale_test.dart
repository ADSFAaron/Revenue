import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Revenue/theme.dart';
import 'package:Revenue/widgets/charts.dart';
import 'package:Revenue/widgets/empty_state.dart';
import 'package:Revenue/widgets/setting_tile.dart';
import 'package:Revenue/widgets/text_scale.dart';

/// The shared furniture, laid out at the font sizes people actually run.
///
/// The system font slider goes to 2x on both platforms and a phone that lives
/// on a kitchen counter is very often near the top of it. Flutter grows the
/// text on its own; what it cannot do is grow the boxes somebody drew around
/// it, so these render the shared widgets on a narrow phone at three sizes and
/// fail on the overflow that used to be found by eye, or not at all.
void main() {
  Widget host(Widget child, {double width = 320}) => MaterialApp(
        theme: MaterialTheme(const TextTheme()).light(),
        home: Scaffold(
          // Scrolling, like the screens these live on: a page that is too
          // tall for the window is not the failure being looked for here — a
          // row that is too wide for it is.
          body: Center(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );

  Future<void> at(WidgetTester tester, double scale, Widget child) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery.withClampedTextScaling(
      minScaleFactor: scale,
      maxScaleFactor: scale,
      child: host(child),
    ));
    await tester.pumpAndSettle();
  }

  const points = [
    ChartPoint(label: '02/28', value: 128400),
    ChartPoint(label: '03/01', value: 96250),
    ChartPoint(label: '03/02', value: 4),
  ];

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('a column chart keeps its axes at ${scale}x', (tester) async {
      await at(
        tester,
        scale,
        const ColumnChart(title: 'Takings', points: points),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ranked bars keep name and figure at ${scale}x',
        (tester) async {
      await at(
        tester,
        scale,
        const RankedBars(
          title: 'Best sellers',
          points: [
            ChartPoint(label: '滷肉飯', value: 312),
            ChartPoint(label: 'A very long dish name indeed', value: 1298400),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('settings rows and empty states survive ${scale}x',
        (tester) async {
      await at(
        tester,
        scale,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingTile.page(
              icon: Icons.restaurant_menu,
              title: 'Menu',
              subtitle: 'Dishes, prices and what they cost you',
              onTap: () {},
            ),
            SettingTile.inline(
              icon: Icons.payments_outlined,
              title: 'Payment methods',
              subtitle: 'Cash, LINE Pay, card',
              trailing: Switch(value: true, onChanged: (_) {}),
            ),
            const SettingSection('Danger zone'),
            const SizedBox(
              height: 320,
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No orders yet',
                body: 'Orders taken on the till show up here.',
              ),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a box that holds text grows with the text', (tester) async {
    late double plain;
    late double capped;
    await tester.pumpWidget(MediaQuery.withClampedTextScaling(
      minScaleFactor: 2.0,
      maxScaleFactor: 2.0,
      child: host(Builder(builder: (context) {
        plain = scaledForText(context, 24);
        capped = scaledForText(context, 24, cap: 1.6);
        return const SizedBox.shrink();
      })),
    ));

    expect(plain, 48);
    // The cap is what stops a twenty-four-column grid walking off the screen;
    // it is not the default, because most boxes only hold their own text.
    expect(capped, closeTo(38.4, 0.001));
  });
}
