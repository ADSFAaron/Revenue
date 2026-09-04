import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the entry screens sit relative to the Navigator, and what that means.
///
/// Both bugs this file pins were invisible until somebody used the app: the
/// root swaps the *home route's* content when the auth state changes, and it
/// has no way to remove routes pushed on top of it. A screen that pushed
/// itself has to take itself off.
void main() {
  testWidgets('swapping the home route leaves pushed routes on top',
      (tester) async {
    // This is the whole shape of the sign-in bug. The root rebuilds with a
    // different home, and the person carries on looking at the form they just
    // filled in — pressing Back was what appeared to complete the sign-in.
    final signedIn = ValueNotifier<bool>(false);
    addTearDown(signedIn.dispose);

    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: signedIn,
        builder: (context, yes, _) => Scaffold(
          body: Center(
            child: yes
                ? const Text('the shell')
                : ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(body: Text('sign in')),
                      ),
                    ),
                    child: const Text('open'),
                  ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('sign in'), findsOneWidget);

    signedIn.value = true;
    await tester.pumpAndSettle();

    // The home route did change underneath — and it is not what anybody sees.
    expect(find.text('sign in'), findsOneWidget);
    expect(find.text('the shell'), findsNothing);

    // Which is why the screen that pushed itself is the one that pops.
    Navigator.of(tester.element(find.text('sign in'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('the shell'), findsOneWidget);
  });

  testWidgets('MaterialApp.builder sits above the Navigator', (tester) async {
    // The till cover is mounted there on purpose, so that it covers pushed
    // routes and dialogs too. The cost is that nothing on it may use
    // `showDialog`: there is no NavigatorState over it to put a route on, and
    // the call throws. The cover asks its questions inline instead.
    late BuildContext fromBuilder;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) {
        fromBuilder = context;
        return child!;
      },
      home: const Scaffold(body: Text('home')),
    ));

    expect(Navigator.maybeOf(fromBuilder), isNull);
  });
}
