import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/widgets/text_scale.dart';

/// The order, kept where it can be read.
///
/// These pin the layout rule rather than the screen: on a window with a spare
/// column the basket is on it, and on a phone the summary bar is the handle
/// that pulls it up. The screen itself needs Firestore to build, so what is
/// testable here is the geometry that decides between the two.
void main() {
  testWidgets('a wide window has room for a column beside the menu',
      (tester) async {
    // 840 is the threshold AddOrder uses. Below it the menu needs the whole
    // width; above it the settings — and now the order — get their own column.
    for (final width in [360.0, 800.0, 900.0, 1400.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      late double panel;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          panel = scaledForText(context, 360, cap: 1.5);
          return const SizedBox();
        }),
      ));
      await tester.pump();

      // The menu must keep a usable share of the window at every width the
      // side column appears at — a panel that grows with the text scale must
      // not be allowed to eat the thing it sits beside.
      if (width >= 840) {
        expect(panel, lessThan(width / 2),
            reason: 'the side column would crowd the menu at $width');
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('the panel grows with the text scale, up to its cap',
      (tester) async {
    late double plain;
    late double scaled;
    late double capped;

    Future<void> at(double factor, void Function(double) sink) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(factor)),
          child: Builder(builder: (context) {
            sink(scaledForText(context, 360, cap: 1.5));
            return const SizedBox();
          }),
        ),
      ));
      await tester.pump();
    }

    await at(1.0, (v) => plain = v);
    await at(1.3, (v) => scaled = v);
    await at(3.0, (v) => capped = v);

    expect(plain, 360);
    expect(scaled, greaterThan(plain));
    // Capped, or a kitchen running at 3x would hand the whole window to four
    // settings and an order.
    expect(capped, 360 * 1.5);
  });
}
