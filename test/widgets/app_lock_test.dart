import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/entry/idle_lock.dart';
import 'package:Revenue/settings/screen_lock.dart';

/// The two structural facts the lock rests on.
///
/// Both were reported from a counter, and neither was a wrong value or a
/// missing branch — each was a widget in the wrong shape, which is why the
/// existing tests all passed while the lock did nothing.
void main() {
  tearDown(() {
    screenLock
      ..value = false
      ..forgetAvailability();
    tillLocked.value = null;
    currentOperator.value = null;
  });

  group('the gate', () {
    /// Whether the shell was ever *built*, not whether it was visible.
    ///
    /// Visibility was never the property that mattered. Every Firestore
    /// stream, the day's takings and the whole of Insights used to be built
    /// and loaded underneath the lock screen, so what the lock protected was a
    /// screenshot rather than the shop's data.
    Widget gate({required VoidCallback onBuilt}) => MaterialApp(
          home: AppLockGate(
            uid: 'u1',
            onLocked: () {},
            child: Builder(
              builder: (context) {
                onBuilt();
                return const Text('the takings');
              },
            ),
          ),
        );

    /// Locked, on a device that answers when asked.
    ///
    /// Stated outright rather than left to the platform: `local_auth` has no
    /// implementation under `flutter_test` and a call into it never answers,
    /// so a test that did not say would sit on a spinner instead of reaching
    /// the branch it is for.
    void locked({required bool canAsk}) => screenLock
      ..debugSetAvailable(canAsk)
      ..value = true;

    testWidgets('builds nothing at all while it is locked', (tester) async {
      locked(canAsk: true);
      var built = false;

      await tester.pumpWidget(gate(onBuilt: () => built = true));
      await tester.pump();
      await tester.pump();

      expect(built, isFalse, reason: 'the shell must not even be constructed');
      expect(find.text('the takings'), findsNothing);
    });

    testWidgets('is not in the way when the lock is off', (tester) async {
      screenLock
        ..debugSetAvailable(true)
        ..value = false;
      var built = false;

      await tester.pumpWidget(gate(onBuilt: () => built = true));
      await tester.pump();

      expect(built, isTrue);
      expect(find.text('the takings'), findsOneWidget);
    });

    testWidgets('a device that cannot ask is told, not let in',
        (tester) async {
      // There is no local_auth platform implementation under a test, which is
      // the same thing the lock sees when a device's enrolment has been
      // removed. It used to answer "unlocked" to that.
      locked(canAsk: false);
      var built = false;

      await tester.pumpWidget(gate(onBuilt: () => built = true));
      // The prompt is raised from a post-frame callback and answers over a
      // couple of microtask turns, so the branch needs a few frames to land.
      for (var i = 0; i < 5; i++) {
        await tester.pump(Duration.zero);
      }

      expect(built, isFalse);
      expect(find.text('Sign in again'), findsOneWidget);
      expect(find.text('Turn the lock off'), findsOneWidget);
    });
  });

  group('the cover', () {
    testWidgets('fills the window', (tester) async {
      // The defect in the screenshots. A `Stack` gives an unpositioned child
      // loose constraints, so the cover took the height of its own text and
      // the live app carried on below it — readable, scrollable and tappable,
      // with a lock screen sitting on the top third of the display.
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => IdleLock(child: child!),
          home: const Scaffold(body: Center(child: Text('the takings'))),
        ),
      );

      tillLocked.value = TillCover.idle;
      await tester.pump();

      expect(
        tester.getSize(find.byType(TillCoverScreen)),
        tester.getSize(find.byType(IdleLock)),
      );
    });

    testWidgets('nothing behind it can be reached', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => IdleLock(child: child!),
          home: Scaffold(
            // Bottom of the screen, which is exactly where the cover used to
            // stop and the live app carried on.
            body: Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: () => tapped = true,
                child: const Text('Add Order'),
              ),
            ),
          ),
        ),
      );

      tillLocked.value = TillCover.idle;
      await tester.pump();

      await tester.tap(find.text('Add Order'), warnIfMissed: false);
      await tester.pump();

      expect(tapped, isFalse);
    });
  });
}
