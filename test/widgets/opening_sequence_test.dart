import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/widgets/logo_mark.dart';
import 'package:Revenue/widgets/opening_sequence.dart';

Widget harness(ValueListenable<bool> ready, {bool stillness = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: stillness),
        child: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: ready,
            builder: (context, value, _) => OpeningSequence(
              ready: value,
              child: const Center(child: Text('the app')),
            ),
          ),
        ),
      ),
    );

/// Runs the sequence to completion so no ticker outlives the test.
Future<void> finish(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

/// A child that notices being torn down and rebuilt.
class _Tenant extends StatefulWidget {
  const _Tenant();

  static int mounted = 0;

  @override
  State<_Tenant> createState() => _TenantState();
}

class _TenantState extends State<_Tenant> {
  @override
  void initState() {
    super.initState();
    _Tenant.mounted++;
  }

  @override
  Widget build(BuildContext context) => const Center(child: Text('the app'));
}

void main() {
  group('the first frame continues the still splash', () {
    test('every ray starts at rest', () {
      // The whole handover rests on this. The native splash has already drawn
      // the mark with its rays where the artwork puts them; if any ray were
      // mid-cycle on the first Flutter frame it would visibly jump.
      for (var i = 0; i < 4; i++) {
        expect(openingRayTravel(0, i), 0);
      }
    });

    test('the staggered rays are what make that non-trivial', () {
      // A moment later they have separated — which is the thing the ramp has
      // to start from nothing without losing.
      final travel = [for (var i = 0; i < 4; i++) openingRayTravel(0.9, i)];
      expect(travel.toSet(), hasLength(4));
      expect(travel.every((t) => t > 0), isTrue);
    });

    test('the pulse stays small and comes back', () {
      for (var t = 0.0; t < 6; t += 0.05) {
        for (var i = 0; i < 4; i++) {
          final travel = openingRayTravel(t, i);
          expect(travel, greaterThanOrEqualTo(0));
          // Two percent of a 1600-unit viewBox. A pulse that grew past this
          // would be a feature rather than a sign of life.
          expect(travel, lessThanOrEqualTo(34.001));
        }
      }
    });
  });

  testWidgets('the mark stays up while the app is not ready', (tester) async {
    final ready = ValueNotifier<bool>(false);
    await tester.pumpWidget(harness(ready));

    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(LogoMark), findsOneWidget);

    ready.value = true;
    await finish(tester);
    expect(find.byType(LogoMark), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('an instant launch still shows the mark for a moment',
      (tester) async {
    // Ready before the first frame is even laid out. Without the minimum hold
    // the mark would appear and vanish inside a couple of frames, which is a
    // flicker rather than a handover.
    final ready = ValueNotifier<bool>(true);
    await tester.pumpWidget(harness(ready));

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(LogoMark), findsOneWidget);

    await finish(tester);
    expect(find.byType(LogoMark), findsNothing);
  });

  testWidgets('reduced motion still hands over, without the movement',
      (tester) async {
    final ready = ValueNotifier<bool>(false);
    await tester.pumpWidget(harness(ready, stillness: true));

    await tester.pump(const Duration(seconds: 2));
    final mark = tester.widget<LogoMark>(find.byType(LogoMark));
    // Held still: the waiting pulse is the part that goes, not the splash.
    expect(mark.rayTravel.every((t) => t == 0), isTrue);

    ready.value = true;
    await finish(tester);
    expect(find.text('the app'), findsOneWidget);
    expect(find.byType(LogoMark), findsNothing);
  });

  testWidgets('the mark covers the screen even when the child has no size',
      (tester) async {
    // The regression that shipped: while auth is still answering, main.dart
    // gives this an empty child on purpose, and a Stack sizes itself from its
    // non-positioned children. With the overlay merely Positioned.fill the
    // whole Stack collapsed to nothing and the app opened to a blank window —
    // no mark, no error, nothing to see in a log.
    final ready = ValueNotifier<bool>(false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: ready,
            builder: (context, value, _) => OpeningSequence(
              ready: value,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    final size = tester.getSize(find.byType(LogoMark));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));

    ready.value = true;
    await finish(tester);
  });

  testWidgets('the app underneath is never rebuilt by the handover',
      (tester) async {
    // The regression that shipped, and the worse half of it. Finishing by
    // returning widget.child on its own moved the child from inside the Stack
    // to the Scaffold's body slot, and Flutter rebuilds an element whose
    // parent has changed. In the app that child is a StreamBuilder on the auth
    // stream: it re-subscribed, went back to `waiting`, and drew the empty box
    // it draws while waiting. A launch that animated correctly and then landed
    // on a blank screen, with nothing in any log to say so.
    _Tenant.mounted = 0;
    final ready = ValueNotifier<bool>(false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: ready,
            builder: (context, value, _) =>
                OpeningSequence(ready: value, child: const _Tenant()),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(_Tenant.mounted, 1);

    ready.value = true;
    await finish(tester);

    expect(find.byType(LogoMark), findsNothing);
    expect(find.text('the app'), findsOneWidget);
    // Mounted once for the whole launch, not once more on the way out.
    expect(_Tenant.mounted, 1);
  });

  testWidgets('the app underneath is built while the mark is still up',
      (tester) async {
    // Not cosmetic: building the first screen behind the cover is what stops
    // the reveal from being the moment a page is laid out for the first time.
    final ready = ValueNotifier<bool>(false);
    await tester.pumpWidget(harness(ready));

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('the app'), findsOneWidget);

    ready.value = true;
    await finish(tester);
  });
}
