import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/entry/idle_lock.dart';
import 'package:Revenue/models/app_user.dart';

/// The cover that goes over a till nobody is standing at.
///
/// The thing worth pinning is what it does NOT do: it never signs anybody out.
/// A timeout that signed out would tear the tree down and take a half-rung-up
/// basket with it every time somebody turned away to make a coffee, which is
/// how a shop ends up setting the timeout to Off.
void main() {
  const operator = AppUser(
    uid: 'u1',
    email: 'ming@example.test',
    displayName: 'Ah-Ming',
    storeId: 'store-1',
  );

  setUp(() {
    currentOperator.value = operator;
    idleTimeout.value = Duration.zero;
    tillLocked.value = null;
  });

  tearDown(() {
    currentOperator.value = null;
    idleTimeout.value = Duration.zero;
    tillLocked.value = null;
  });

  /// Mounted the way `main()` mounts it: from `MaterialApp.builder`, which is
  /// *above* the Navigator. That is what lets the cover sit over pushed routes
  /// and dialogs, and it is also what stops anything on the cover using
  /// `showDialog` — there is no NavigatorState over it to put a route on.
  /// Mounting it as `home` in a test would hide that, which is exactly what it
  /// did until a probe went looking.
  Widget app({Widget? body}) => MaterialApp(
        builder: (context, child) => IdleLock(child: child!),
        home: Scaffold(
          body: body ??
              const Center(child: Text('the takings')),
        ),
      );

  testWidgets('off means it never covers itself', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(minutes: 30));

    expect(find.text('the takings'), findsOneWidget);
    expect(find.text('Carry on'), findsNothing);
  });

  testWidgets('covers the till after the store\'s own interval',
      (tester) async {
    idleTimeout.value = const Duration(minutes: 2);
    await tester.pumpWidget(app());

    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Carry on'), findsNothing);

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(find.text('Carry on'), findsOneWidget);
    // Whose session it is, said rather than shown: the point of covering a
    // counter is that what is behind the cover is not readable across it.
    expect(find.text('Ah-Ming'), findsOneWidget);
  });

  testWidgets('a touch anywhere puts the clock back', (tester) async {
    idleTimeout.value = const Duration(minutes: 2);
    await tester.pumpWidget(app());

    await tester.pump(const Duration(seconds: 90));
    await tester.tap(find.text('the takings'));
    await tester.pump(const Duration(seconds: 90));

    expect(find.text('Carry on'), findsNothing);
  });

  testWidgets('carrying on puts the same screen back, untouched',
      (tester) async {
    idleTimeout.value = const Duration(minutes: 1);
    await tester.pumpWidget(app());
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(find.text('Carry on'), findsOneWidget);

    await tester.tap(find.text('Carry on'));
    await tester.pumpAndSettle();

    expect(find.text('Carry on'), findsNothing);
    expect(find.text('the takings'), findsOneWidget);
  });

  testWidgets('handing over is offered', (tester) async {
    idleTimeout.value = const Duration(minutes: 1);
    await tester.pumpWidget(app());
    await tester.pump(const Duration(minutes: 1, seconds: 1));

    expect(find.text('Hand over to'), findsOneWidget);
    expect(find.text('Somebody else'), findsOneWidget);
  });

  testWidgets('a basket with something in it is worth a warning',
      (tester) async {
    // Handing over always costs the basket — an order half rung up by one
    // person must not arrive under somebody else's name — but asking every
    // time would be friction on the exact operation this is meant to make
    // cheap. So the question is asked only when there is an answer to it.
    unsentBasketLines.value = 3;
    addTearDown(() => unsentBasketLines.value = 0);

    idleTimeout.value = const Duration(minutes: 1);
    await tester.pumpWidget(app());
    await tester.pump(const Duration(minutes: 1, seconds: 1));

    await tester.tap(find.text('Somebody else'));
    await tester.pumpAndSettle();

    // No exception, which is the half of this that matters: the question is
    // asked on the cover itself rather than through a Navigator that is not
    // above it.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('3 dishes have been rung up'), findsOneWidget);

    // The cover scrolls: the warning is longer than a short phone.
    await tester.ensureVisible(find.text('Go back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(find.text('Carry on'), findsOneWidget);
  });

  testWidgets('nobody signed in is nobody to cover', (tester) async {
    currentOperator.value = null;
    idleTimeout.value = const Duration(minutes: 1);
    await tester.pumpWidget(app());
    await tester.pump(const Duration(minutes: 2));

    expect(find.text('Carry on'), findsNothing);
  });

  testWidgets('the operator chip covers the till on demand', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => IdleLock(child: child!),
      home: Scaffold(
        appBar: AppBar(actions: const [OperatorChip()]),
        body: const SizedBox(),
      ),
    ));

    expect(find.text('Ah-Ming'), findsOneWidget);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    expect(find.text('Carry on'), findsOneWidget);
  });
}
