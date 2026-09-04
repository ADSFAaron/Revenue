import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/entry/choose_path.dart';
import 'package:Revenue/entry/entry_button.dart';
import 'package:Revenue/entry/entry_ui.dart';
import 'package:Revenue/theme.dart';

ThemeData themeFor(Brightness brightness) => brightness == Brightness.dark
    ? MaterialTheme(const TextTheme()).dark()
    : MaterialTheme(const TextTheme()).light();

Widget wrap(Widget child, Brightness brightness) =>
    MaterialApp(theme: themeFor(brightness), home: child);

void main() {
  group('the screens before sign-in survive a dark phone', () {
    // These were pinned to the light palette by a theme that no longer exists,
    // and then to two SVGs per drawing that no longer exist either. Rendering
    // them under the dark theme is still the test: black text on a black
    // ground throws nothing, but an overflow does.
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final name = brightness == Brightness.dark ? 'dark' : 'light';

      testWidgets('the get-started chooser lays out in $name', (tester) async {
        // 320 is narrower than any phone this ships to, on purpose: the
        // "Already have an account?" line and its button overflowed a Row by
        // more than a hundred points at 400.
        await tester.binding.setSurfaceSize(const Size(320, 640));
        await tester.pumpWidget(wrap(const ChoosePathScreen(), brightness));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('the header draws the mark in $name', (tester) async {
        // The mark is geometry now rather than an asset per mode, so there is
        // no file to be missing — but it is painted from theme-dependent
        // colours, and a wrong one throws here rather than at a shop's till.
        await tester.pumpWidget(
          wrap(const Scaffold(body: EntryHeader(tagline: 'Hello')), brightness),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Revenue'), findsOneWidget);
      });
    }
  });

  group('the shared action button', () {
    testWidgets('busy refuses the tap and keeps its height', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(
        Scaffold(
          body: EntryButton(
            label: 'Sign in',
            busy: true,
            onPressed: () => taps++,
          ),
        ),
        Brightness.light,
      ));

      expect(find.text('Sign in'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(EntryButton));
      await tester.pump();
      expect(taps, 0);
      // The page must not resettle under a thumb that is already moving.
      expect(tester.getSize(find.byType(EntryButton)).height, 60);
    });

    testWidgets('outlined and filled are different buttons', (tester) async {
      await tester.pumpWidget(wrap(
        Scaffold(
          body: Column(
            children: [
              EntryButton(label: 'Filled', onPressed: () {}),
              EntryButton.outlined(label: 'Outlined', onPressed: () {}),
            ],
          ),
        ),
        Brightness.light,
      ));

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('a null callback disables it', (tester) async {
      await tester.pumpWidget(wrap(
        const Scaffold(body: EntryButton(label: 'Next', onPressed: null)),
        Brightness.light,
      ));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });
  });
}
