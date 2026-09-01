import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/widgets/setting_tile.dart';

/// Two rules this app got wrong for a long time, now pinned down.
///
/// The first is that a store assistant was shown twelve tappable settings
/// rows, eight of which `firestore.rules` refuses to let them write. Every one
/// of those taps opened a dialog, accepted a value and failed on save. The
/// screens ask for the role now, and a locked row has to keep showing its
/// value — somebody reconciling a drawer needs to read the tax rate even
/// though they may not change it.
///
/// The second is that the chevron meant nothing: it sat on rows that pushed a
/// screen and on rows that opened a dialog, so it could not be used to predict
/// either.
void main() {
  Future<void> show(WidgetTester tester, Widget tile) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ListView(children: [tile]))),
      );

  final chevron = find.byIcon(Icons.keyboard_arrow_right_rounded);
  final padlock = find.byIcon(Icons.lock_outline_rounded);

  group('the chevron means exactly one thing', () {
    testWidgets('a row that opens a screen has one', (tester) async {
      await show(
        tester,
        SettingTile.page(
          icon: Icons.storefront_outlined,
          title: 'Payment methods',
          onTap: () {},
        ),
      );

      expect(chevron, findsOneWidget);
    });

    testWidgets('a row that edits in place does not', (tester) async {
      await show(
        tester,
        SettingTile.inline(
          icon: Icons.percent_outlined,
          title: 'Tax',
          subtitle: '5% · included in prices',
          onTap: () {},
        ),
      );

      expect(chevron, findsNothing);
      expect(find.text('5% · included in prices'), findsOneWidget);
    });

    testWidgets('a row that only reports a value does not', (tester) async {
      await show(
        tester,
        const SettingTile.readOnly(
          icon: Icons.badge_outlined,
          title: 'Role',
          subtitle: 'Owner',
        ),
      );

      expect(chevron, findsNothing);
    });
  });

  group('a locked row', () {
    late int taps;

    Future<void> showLocked(WidgetTester tester) async {
      taps = 0;
      await show(
        tester,
        SettingTile.inline(
          icon: Icons.percent_outlined,
          title: 'Tax',
          subtitle: '5% · included in prices',
          locked: true,
          onTap: () => taps++,
        ),
      );
    }

    testWidgets('does not run its action when tapped', (tester) async {
      await showLocked(tester);
      await tester.tap(find.text('Tax'));
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('still shows the value behind it', (tester) async {
      await showLocked(tester);

      // The whole reason it is locked rather than hidden.
      expect(find.text('5% · included in prices'), findsOneWidget);
    });

    testWidgets('says who may change it, before it is tapped', (tester) async {
      await showLocked(tester);

      expect(padlock, findsOneWidget);
      expect(find.text('Managers only'), findsOneWidget);
    });

    testWidgets('replaces the chevron rather than sitting beside it',
        (tester) async {
      await show(
        tester,
        SettingTile.page(
          icon: Icons.fact_check_outlined,
          title: 'Change history',
          locked: true,
          onTap: () {},
        ),
      );

      expect(padlock, findsOneWidget);
      expect(chevron, findsNothing);
    });
  });
}
