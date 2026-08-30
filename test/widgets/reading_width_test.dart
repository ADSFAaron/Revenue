import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Revenue/widgets/page_body.dart';

/// The distinction [ReadingWidth] exists for.
///
/// Capping a page's width by wrapping its `ListView` in a `ConstrainedBox`
/// looks identical to insetting the list's own padding — until a mouse is
/// involved. Flutter routes a scroll wheel event to the `Scrollable` under the
/// pointer, so a narrowed list leaves the page either side of it dead. On a
/// phone nothing shows it; on the browser the app is actually used in, half
/// the window stops scrolling.
void main() {
  Future<double> wheelAt(WidgetTester tester, Offset at) async {
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final before = position.pixels;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    tester.binding.handlePointerEvent(pointer.hover(at));
    tester.binding.handlePointerEvent(pointer.scroll(const Offset(0, 300)));
    await tester.pump();
    return position.pixels - before;
  }

  Widget host(Widget body) => MaterialApp(home: Scaffold(body: body));

  final rows = [for (var i = 0; i < 60; i++) ListTile(title: Text('row $i'))];

  testWidgets('ReadingWidth keeps the whole page scrollable', (tester) async {
    tester.view.physicalSize = const Size(1600, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      ReadingWidth(
        builder: (context, insets) =>
            ListView(padding: insets, children: rows),
      ),
    ));

    expect(await wheelAt(tester, const Offset(800, 300)), 300,
        reason: 'wheel over the content');
    expect(await wheelAt(tester, const Offset(60, 300)), 300,
        reason: 'wheel over the margin beside the content');
  });

  testWidgets('the constraint it replaced left the margins dead',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // What PageBody around a scrollable does — kept here as the counter-example
    // so the difference stays visible rather than being a claim in a comment.
    await tester.pumpWidget(host(
      PageBody(child: ListView(children: rows)),
    ));

    expect(await wheelAt(tester, const Offset(800, 300)), 300);
    expect(await wheelAt(tester, const Offset(60, 300)), 0);
  });

  testWidgets('ReadingWidth adds nothing when the window is narrow',
      (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late EdgeInsets seen;
    await tester.pumpWidget(host(
      ReadingWidth(
        builder: (context, insets) {
          seen = insets;
          return ListView(padding: insets, children: rows);
        },
      ),
    ));

    expect(seen, EdgeInsets.zero);
  });
}
