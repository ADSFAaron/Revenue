import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/database/data_exception.dart';
import 'package:Revenue/widgets/feedback.dart';

/// The one rule every failure path in this app has to keep: what reaches a
/// shop owner is a sentence, never a code.
///
/// Both of the bugs this file was written after looked like this in the
/// source — `'An error occurred: ${snapshot.error}'` on the first screen the
/// app draws, and `'Could not join the store: $e'` halfway through an invite —
/// and both put `[cloud_firestore/permission-denied]` in front of somebody who
/// can do nothing with it. `describeFailure` existed the whole time; those two
/// call sites simply were not using it.
void main() {
  Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: child)),
      );

  final firestoreError = FirebaseException(
    plugin: 'cloud_firestore',
    code: 'permission-denied',
    message: 'Missing or insufficient permissions.',
  );

  testWidgets('ErrorView translates a Firebase failure', (tester) async {
    await show(tester, ErrorView(firestoreError));

    expect(find.textContaining('permission to do that'), findsOneWidget);
    expect(find.textContaining('cloud_firestore'), findsNothing);
    expect(find.textContaining('['), findsNothing);
  });

  testWidgets('InlineError translates a Firebase failure', (tester) async {
    await show(tester, InlineError(firestoreError));

    expect(find.textContaining('permission to do that'), findsOneWidget);
    expect(find.textContaining('cloud_firestore'), findsNothing);
  });

  testWidgets('InlineError offers Retry only when given something to retry',
      (tester) async {
    await show(tester, InlineError(firestoreError));
    expect(find.text('Retry'), findsNothing);

    var retried = 0;
    await show(tester, InlineError(firestoreError, onRetry: () => retried++));
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('an app exception keeps its own wording', (tester) async {
    await show(
      tester,
      const InlineError(
        DataException(DataFailure.offline, 'The till is offline.'),
      ),
    );

    expect(find.text('The till is offline.'), findsOneWidget);
  });

  testWidgets('a plain Error still ends as a sentence', (tester) async {
    // `catch (e)` catches `Error` too — a document that does not hold what the
    // model expects arrives as a TypeError, and it must not reach the screen
    // as a stack trace.
    await show(tester, ErrorView(ArgumentError('bad doc')));

    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
  });
}
