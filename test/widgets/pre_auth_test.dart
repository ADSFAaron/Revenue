import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/main.dart';
import 'package:Revenue/register.dart';
import 'package:Revenue/theme.dart';
import 'package:Revenue/widgets/illustration.dart';
import 'package:Revenue/widgets/pre_auth_button.dart';

ThemeData themeFor(Brightness brightness) => brightness == Brightness.dark
    ? MaterialTheme(const TextTheme()).dark()
    : MaterialTheme(const TextTheme()).light();

Widget wrap(Widget child, Brightness brightness) =>
    MaterialApp(theme: themeFor(brightness), home: child);

void main() {
  group('the screens before sign-in survive a dark phone', () {
    // These were pinned to the light palette by pre_auth_theme.dart, which is
    // now gone. Rendering them under the dark theme at all is the test: black
    // text on a black ground throws nothing, but a missing asset for the mode
    // and any overflow do.
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final name = brightness == Brightness.dark ? 'dark' : 'light';

      testWidgets('welcome lays out in $name', (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        await tester.pumpWidget(wrap(const WelcomeScreen(), brightness));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('the register chooser lays out in $name', (tester) async {
        // 320 is narrower than any phone this ships to, on purpose: the
        // "Already have an account?" line and its button overflowed a Row by
        // more than a hundred points at 400.
        await tester.binding.setSurfaceSize(const Size(320, 640));
        await tester.pumpWidget(wrap(const RegisterPage(), brightness));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('both illustrations have a $name file', (tester) async {
        // An asset declared in pubspec.yaml but never loaded, or loaded but
        // never declared, only fails at run time — and only in one mode.
        for (final art in ['welcome', 'login_bg']) {
          await tester.pumpWidget(wrap(Illustration(art), brightness));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$art in $name');
        }
      });
    }
  });

  group('the shared action button', () {
    testWidgets('busy refuses the tap and keeps its height', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(
        Scaffold(
          body: PreAuthButton(
            label: 'Login',
            busy: true,
            onPressed: () => taps++,
          ),
        ),
        Brightness.light,
      ));

      expect(find.text('Login'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(PreAuthButton));
      await tester.pump();
      expect(taps, 0);
      // The page must not resettle under a thumb that is already moving.
      expect(tester.getSize(find.byType(PreAuthButton)).height, 60);
    });

    testWidgets('outlined and filled are different buttons', (tester) async {
      await tester.pumpWidget(wrap(
        Scaffold(
          body: Column(
            children: [
              PreAuthButton(label: 'Filled', onPressed: () {}),
              PreAuthButton.outlined(label: 'Outlined', onPressed: () {}),
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
        const Scaffold(body: PreAuthButton(label: 'Next', onPressed: null)),
        Brightness.light,
      ));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });
  });
}
