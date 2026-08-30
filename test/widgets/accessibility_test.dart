import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Revenue/theme.dart';
import 'package:Revenue/widgets/feedback.dart';
import 'package:Revenue/widgets/stat_card.dart';

/// Runs Flutter's own accessibility guidelines over the shared widgets.
///
/// These were checked by eye until now, which is how a 40x40 tap target and a
/// 1.6:1 icon got in. The guidelines are cheap to run and do not have opinions
/// about how something looks — only whether it can be operated and read.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    final theme = brightness == Brightness.light
        ? MaterialTheme(const TextTheme()).light()
        : MaterialTheme(const TextTheme()).dark();
    return MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  for (final brightness in Brightness.values) {
    final label = brightness.name;

    testWidgets('$label: stat cards meet contrast and tap targets',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        Wrap(
          children: [
            StatCard(
              title: 'Revenue',
              value: 'NT\$12,345',
              icon: Icons.savings_rounded,
              onTap: () {},
              trailing: const ChangeBadge(change: 0.12),
            ),
            StatCard(
              title: 'Orders',
              value: '87',
              icon: Icons.receipt_long_outlined,
              trailing: const ChangeBadge(change: -0.08),
            ),
            const StatCard(title: 'Guests', value: '0'),
          ],
        ),
        brightness: brightness,
      ));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('$label: error view meets contrast and tap targets',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        ErrorView(
          Exception('no connection'),
          onRetry: () {},
        ),
        brightness: brightness,
      ));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('$label: destructive button meets contrast and tap targets',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: () {}, child: const Text('Cancel')),
            DestructiveButton(label: 'Delete', onPressed: () {}),
          ],
        ),
        brightness: brightness,
      ));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  }

  // A kitchen phone is very often on a large system font, and the failure
  // mode is not "slightly cramped" — it is a yellow-and-black overflow stripe
  // where a number should be.
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('stat cards survive a ${scale}x text scale', (tester) async {
      // `builder` rather than wrapping in a bare MediaQuery: replacing the
      // whole MediaQueryData wipes `size` to zero, and anything sizing itself
      // from the window then gets negative constraints.
      await tester.pumpWidget(MediaQuery.withClampedTextScaling(
        minScaleFactor: scale,
        maxScaleFactor: scale,
        child: host(
          SizedBox(
            width: 380,
            child: Wrap(
              children: [
                StatCard(
                  title: 'Gross profit',
                  value: 'NT\$1,234,567',
                  icon: Icons.trending_up_rounded,
                  trailing: const ChangeBadge(change: -0.08),
                ),
                const StatCard(title: 'Per head', value: 'NT\$285'),
              ],
            ),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('every tappable thing has a label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatCard(
            title: 'Revenue',
            value: 'NT\$1',
            icon: Icons.savings_rounded,
            onTap: () {},
          ),
          DestructiveButton(label: 'Delete', onPressed: () {}),
        ],
      ),
    ));

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
