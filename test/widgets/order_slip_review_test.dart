import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/models/menu_item.dart';
import 'package:Revenue/models/order_slip.dart';
import 'package:Revenue/models/store.dart';
import 'package:Revenue/page/order_slip_review.dart';

/// The screen that stands between a photograph and the takings.
///
/// It exists to be in the way, so what is pinned is that it cannot be got past
/// without a decision: every line is shown, quantities are editable, and only
/// what survives that reaches the basket. A slip read into an order and
/// submitted unseen would be a figure nobody checked — and unlike a mis-tapped
/// dish, nobody would ever know which order was wrong or by how much.
void main() {
  const store = Store(id: 's1', name: 'Test');
  const menu = [
    MenuItem(id: 'noodles', name: 'Beef Noodles', price: 130),
    MenuItem(id: 'rice', name: 'Braised Rice', price: 60),
  ];

  Future<Map<String, int>?> run(
    WidgetTester tester,
    SlipReading reading, {
    Future<void> Function(WidgetTester tester)? act,
  }) async {
    Map<String, int>? returned;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            returned = await Navigator.of(context).push<Map<String, int>>(
              MaterialPageRoute(
                builder: (_) => OrderSlipReview(
                  reading: reading,
                  menu: menu,
                  store: store,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (act != null) await act(tester);
    return returned;
  }

  testWidgets('every line is shown, unsure ones first', (tester) async {
    await run(
      tester,
      const SlipReading(lines: [
        SlipLine(itemId: 'noodles', qty: 1),
        SlipLine(itemId: 'rice', qty: 2, sure: false),
      ]),
    );

    expect(find.text('Beef Noodles'), findsOneWidget);
    expect(find.text('Braised Rice'), findsOneWidget);

    final rice = tester.getTopLeft(find.text('Braised Rice')).dy;
    final noodles = tester.getTopLeft(find.text('Beef Noodles')).dy;
    expect(rice, lessThan(noodles), reason: 'the hedged line is checked first');
  });

  testWidgets('confirming returns what is on screen, not what was read',
      (tester) async {
    final returned = await run(
      tester,
      const SlipReading(lines: [
        SlipLine(itemId: 'noodles', qty: 1),
        SlipLine(itemId: 'rice', qty: 2),
      ]),
      act: (tester) async {
        // One more of the noodles, and drop the rice entirely.
        await tester.tap(find.byIcon(Icons.add_circle_outline).first);
        await tester.pump();
        await tester.tap(find.byIcon(Icons.remove_circle_outline).last);
        await tester.pump();
        await tester.tap(find.byIcon(Icons.remove_circle_outline).last);
        await tester.pump();
        await tester.tap(find.text('Add to the order'));
        await tester.pumpAndSettle();
      },
    );

    expect(returned, {'noodles': 2},
        reason: 'a line taken to zero is not added at all');
  });

  testWidgets('nothing can be added when everything has been zeroed',
      (tester) async {
    await run(
      tester,
      const SlipReading(lines: [SlipLine(itemId: 'rice', qty: 1)]),
      act: (tester) async {
        await tester.tap(find.byIcon(Icons.remove_circle_outline));
        await tester.pump();
      },
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add to the order'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('writing that is not on the menu is shown, not dropped',
      (tester) async {
    // Somebody holding the slip can see there is writing on it that did not
    // make it into the basket. A reader that quietly ignored it would be
    // teaching them not to check.
    await run(
      tester,
      const SlipReading(
        lines: [SlipLine(itemId: 'rice', qty: 1)],
        unreadable: ['加辣', '今日特餐'],
      ),
    );

    expect(find.text('· 加辣'), findsOneWidget);
    expect(find.text('· 今日特餐'), findsOneWidget);
  });

  testWidgets('an id that is not on this menu never reaches the screen',
      (tester) async {
    // The server drops these and returns a count. Belt and braces: the screen
    // renders from the menu it was given, so a line it cannot price cannot be
    // drawn at all.
    await run(
      tester,
      const SlipReading(
        lines: [SlipLine(itemId: 'ghost-dish', qty: 3)],
        unmatched: 1,
      ),
    );

    expect(find.textContaining('not on this menu'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
  });
}
