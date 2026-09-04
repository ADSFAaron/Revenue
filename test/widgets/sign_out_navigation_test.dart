import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What lib/main.dart does when a session ends, in miniature.
///
/// The real listener lives in `_HomePageState` and reaches FirebaseAuth, so it
/// cannot be driven from a test. What is worth pinning here is the shape:
/// popping every route above the root from a stream callback, while a dialog
/// may still be animating out. Signing out is exactly that — Account & App pops
/// its confirmation dialog, calls signOut, and the auth stream fires while the
/// dialog is mid-transition.
void main() {
  testWidgets('a session ending clears the routes it belonged to',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final auth = StreamController<String?>.broadcast();
    auth.stream.listen((uid) {
      if (uid == null) key.currentState?.popUntil((route) => route.isFirst);
    });

    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _AccountAndApp()),
            ),
            child: const Text('root'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('root'));
    await tester.pumpAndSettle();
    expect(find.text('root'), findsNothing);

    await tester.tap(find.text('log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('confirm'));

    // The dialog has begun its exit and the stream fires underneath it. Popping
    // routes at the wrong moment is how the delete-account dialog in this app
    // once took the whole app to a red screen, so the timing is the test.
    await tester.pump();
    auth.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Back at the root, rather than left on a page belonging to a session that
    // no longer exists — which is what the reader saw before, under the words
    // "You do not have permission to do that".
    expect(find.text('root'), findsOneWidget);

    // Closing the controller takes the subscription with it. Awaiting
    // `cancel()` on its own hangs here: a widget test drives its own clock, and
    // that future never gets one.
    await auth.close();
  });
}

class _AccountAndApp extends StatelessWidget {
  const _AccountAndApp();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                content: const Text('Log out?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('confirm'),
                  ),
                ],
              ),
            ),
            child: const Text('log out'),
          ),
        ),
      );
}
