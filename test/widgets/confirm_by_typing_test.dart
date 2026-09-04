import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/widgets/confirm_by_typing.dart';

Future<String?> open(WidgetTester tester) async {
  String? answer;
  var returned = false;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            answer = await confirmByTyping(
              context,
              title: 'Type the store name to confirm',
              phrase: 'Shop',
              fieldLabel: 'Store name',
              confirmLabel: 'Delete everything',
            );
            returned = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(returned, isFalse);
  return answer;
}

void main() {
  testWidgets('closing does not take the app down with it', (tester) async {
    // The crash this file exists to prevent. The controller used to be created
    // beside showDialog and disposed in its whenComplete, which fires as the
    // route is popped — while the TextField is still mounted and still reading
    // it. The exit transition then failed an assertion deep in the framework
    // ('_dependents.isEmpty': is not true) and the app went to a red screen, on
    // the last confirmation of an irreversible action.
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Shop');
    await tester.pump();

    await tester.tap(find.text('Delete everything'));
    // Through the whole exit transition, which is where it used to fail.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('cancelling survives it too', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'anything');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wrong name cannot be confirmed at all', (tester) async {
    // What was reported: typing anything and pressing the button appeared to
    // work, because the server's check was never reached — App Check had
    // already refused the call, and the round trip came back "Your session
    // expired". Answered here now, before anything leaves the phone.
    await open(tester);
    await tester.enterText(find.byType(TextField), 'not the shop name');
    await tester.pump();

    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Delete everything'),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Delete everything'));
    await tester.pumpAndSettle();
    // Still open, because nothing happened.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a trailing space is not a typo', (tester) async {
    // A name copied off a sign carries one more often than it carries a
    // mistake, and the server trims too.
    String? answer;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await confirmByTyping(
              context,
              title: 'Type the store name to confirm',
              phrase: 'Shop',
              fieldLabel: 'Store name',
              confirmLabel: 'Delete everything',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Shop ');
    await tester.pump();
    await tester.tap(find.text('Delete everything'));
    await tester.pumpAndSettle();
    expect(answer, '  Shop ');
  });

  testWidgets('the right name hands back what was typed', (tester) async {
    String? answer;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await confirmByTyping(
              context,
              title: 'Type the store name to confirm',
              phrase: 'Shop',
              fieldLabel: 'Store name',
              confirmLabel: 'Delete everything',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Shop');
    await tester.pump();
    await tester.tap(find.text('Delete everything'));
    await tester.pumpAndSettle();

    expect(answer, 'Shop');
    expect(tester.takeException(), isNull);
  });

  testWidgets('backing out gives nothing', (tester) async {
    String? answer = 'untouched';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await confirmByTyping(
              context,
              title: 'Type the store name to confirm',
              phrase: 'Shop',
              fieldLabel: 'Store name',
              confirmLabel: 'Delete everything',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answer, isNull);
  });

  testWidgets('the keyboard action confirms as well as the button',
      (tester) async {
    // The button sits under the keyboard on a phone once the field has focus.
    String? answer;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await confirmByTyping(
              context,
              title: 'Type the store name to confirm',
              phrase: 'Shop',
              fieldLabel: 'Store name',
              confirmLabel: 'Delete everything',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Shop');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(answer, 'Shop');
    expect(tester.takeException(), isNull);
  });
}
