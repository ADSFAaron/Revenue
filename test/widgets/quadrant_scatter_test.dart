import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/widgets/quadrant_scatter.dart';

QuadrantPoint pointAt(String label, double x, double y) => QuadrantPoint(
      label: label,
      x: x,
      y: y,
      color: const Color(0xFF4A672D),
      detail: '$label detail',
    );

Widget harness(
  List<QuadrantPoint> points, {
  double xThreshold = 0.2,
  double yThreshold = 10,
  double width = 400,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: QuadrantScatter(
              points: points,
              xThreshold: xThreshold,
              yThreshold: yThreshold,
              xAxisLabel: 'Share of units sold',
              yAxisLabel: 'Margin each',
              quadrantLabels: (
                topLeft: 'Puzzle',
                topRight: 'Star',
                bottomLeft: 'Dog',
                bottomRight: 'Plowhorse',
              ),
              formatX: (v) => v.toStringAsFixed(2),
              formatY: (v) => v.toStringAsFixed(0),
            ),
          ),
        ),
      ),
    );

/// The dot for a given dish.
///
/// Matched on the widget tree rather than with `find.bySemanticsLabel`, which
/// reads the *semantics* tree — and there a lone dot gets merged into the
/// tappable plot around it, so the one-dish case would look like a missing dot
/// when the dot is drawn correctly. What these tests are about is where the dot
/// was placed, which is a widget-tree question.
Finder dot(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

Offset dotCentre(WidgetTester tester, String label) =>
    tester.getCenter(dot(label));

void main() {
  testWidgets('a dish either side of a threshold lands either side of the line',
      (tester) async {
    await tester.pumpWidget(harness([
      // Same margin, one above the popularity threshold and one below.
      pointAt('Popular', 0.30, 20),
      pointAt('Unpopular', 0.10, 20),
    ]));

    expect(dotCentre(tester, 'Popular').dx,
        greaterThan(dotCentre(tester, 'Unpopular').dx));
  });

  testWidgets('a bigger margin is drawn higher, not lower', (tester) async {
    await tester.pumpWidget(harness([
      pointAt('Rich', 0.3, 40),
      pointAt('Thin', 0.3, 5),
    ]));

    // Screens count downward, so "higher up" is a smaller dy. Getting this
    // backwards would still produce a plausible-looking chart, which is exactly
    // why it is worth a test.
    expect(dotCentre(tester, 'Rich').dy, lessThan(dotCentre(tester, 'Thin').dy));
  });

  testWidgets('a dish that sells below cost stays on the chart',
      (tester) async {
    await tester.pumpWidget(harness([
      pointAt('Loss maker', 0.3, -50),
      pointAt('Earner', 0.3, 40),
    ]));

    final loss = dotCentre(tester, 'Loss maker');
    final earner = dotCentre(tester, 'Earner');
    expect(loss.dy, greaterThan(earner.dy));
    // Inside the plot rather than clipped off the bottom edge of it.
    expect(loss.dy, lessThan(tester.getBottomLeft(find.byKey(QuadrantScatter.plotKey)).dy));
  });

  testWidgets('tapping a dot names the dish, tapping away clears it',
      (tester) async {
    await tester.pumpWidget(harness([
      pointAt('Beef Noodles', 0.3, 40),
      pointAt('Oolong', 0.05, 15),
    ]));

    expect(find.text('Tap a dot to see which dish it is.'), findsOneWidget);
    expect(find.text('Beef Noodles detail'), findsNothing);

    await tester.tap(dot('Beef Noodles'));
    await tester.pump();
    expect(find.text('Beef Noodles detail'), findsOneWidget);

    // A corner no dot is near.
    await tester.tapAt(tester.getTopLeft(find.byKey(QuadrantScatter.plotKey)) +
        const Offset(2, 2));
    await tester.pump();
    expect(find.text('Beef Noodles detail'), findsNothing);
  });

  testWidgets('the thresholds stay on the chart when no dish is near them',
      (tester) async {
    // Every dish far below the average margin — the horizontal rule would fall
    // off the top of the plot if the bounds only covered the data.
    await tester.pumpWidget(harness(
      [pointAt('A', 0.02, 1), pointAt('B', 0.03, 2)],
      xThreshold: 0.5,
      yThreshold: 90,
    ));

    // The axis prints the threshold, and it is between the two ends.
    expect(find.text('90'), findsOneWidget);
    final plot = find.byKey(QuadrantScatter.plotKey);
    final top = tester.getTopLeft(plot).dy;
    final bottom = tester.getBottomLeft(plot).dy;
    final label = tester.getCenter(find.text('90')).dy;
    expect(label, greaterThanOrEqualTo(top));
    expect(label, lessThanOrEqualTo(bottom));
  });

  testWidgets('one dish alone does not divide by a zero-width range',
      (tester) async {
    await tester.pumpWidget(harness(
      [pointAt('Only', 0.25, 25)],
      xThreshold: 0.25,
      yThreshold: 25,
    ));

    final centre = dotCentre(tester, 'Only');
    expect(centre.dx.isFinite, isTrue);
    expect(centre.dy.isFinite, isTrue);
  });

  testWidgets('an empty menu says so instead of drawing an empty grid',
      (tester) async {
    await tester.pumpWidget(harness(const []));
    expect(find.text('Nothing to place yet.'), findsOneWidget);
  });
}
