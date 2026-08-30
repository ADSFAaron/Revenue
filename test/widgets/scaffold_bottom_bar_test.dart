import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The trap that ate the menu viewfinder.
///
/// `MenuCapturePage` put its shutter in `bottomNavigationBar: SafeArea(Padding(
/// Center(child: shutter)))`, which reads as "a 72dp button, centred, with some
/// breathing room". It measured 960dp — the whole window — because Scaffold
/// hands that slot `BoxConstraints.loose(size)`, and a bare `Center` is an
/// `Align` with no size factors. `RenderPositionedBox` shrink-wraps an axis
/// only when that axis is *unbounded*; given a bounded one it takes all of it.
///
/// The result was not a slightly tall bar. Scaffold gives the body what the
/// bottom bar leaves, so the body got nothing, the camera preview was laid out
/// at zero height, and the only thing on a black screen was a shutter sitting
/// at the exact vertical centre — which is what made it read as "the camera is
/// broken" rather than as a layout mistake. The sensor had been opening
/// correctly the whole time.
///
/// This tests the pattern rather than the page: the page needs a camera plugin
/// to build, and the bug was never in the camera half.
void main() {
  const shutter = SizedBox(key: Key('shutter'), width: 72, height: 72);

  Widget host(Widget bar) => MaterialApp(
        home: Scaffold(
          body: Container(key: const Key('body'), color: Colors.black),
          bottomNavigationBar: bar,
        ),
      );

  testWidgets('a shutter bar is the height of its shutter, not the window',
      (tester) async {
    await tester.pumpWidget(host(
      const SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(heightFactor: 1, child: shutter),
        ),
      ),
    ));

    // 72 for the button, 24 above and below.
    expect(tester.getSize(find.byType(SafeArea)).height, 120);
  });

  testWidgets('and leaves the body the rest of the window', (tester) async {
    await tester.pumpWidget(host(
      const SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(heightFactor: 1, child: shutter),
        ),
      ),
    ));

    final window = tester.getSize(find.byType(MaterialApp)).height;
    final body = tester.getSize(find.byKey(const Key('body'))).height;

    expect(body, window - 120);
    expect(body, greaterThan(0));
  });

  testWidgets('without heightFactor the bar swallows the whole window',
      (tester) async {
    await tester.pumpWidget(host(
      const SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: shutter),
        ),
      ),
    ));

    // The shipped bug, pinned so nobody restores it by "tidying up" the
    // heightFactor: the bar fills the window and the body is left with nothing
    // to draw a viewfinder in.
    final window = tester.getSize(find.byType(MaterialApp)).height;
    expect(tester.getSize(find.byType(SafeArea)).height, window);
    expect(tester.getSize(find.byKey(const Key('body'))).height, 0);
  });
}
