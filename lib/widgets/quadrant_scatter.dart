import 'package:flutter/material.dart';

import 'text_scale.dart';

/// One dish on the matrix.
class QuadrantPoint {
  const QuadrantPoint({
    required this.label,
    required this.x,
    required this.y,
    required this.color,
    required this.detail,
  });

  final String label;

  /// Horizontal position in the same units the axis is labelled in.
  final double x;

  /// Vertical position, likewise. May be negative — a dish can sell below what
  /// it costs to make.
  final double y;

  final Color color;

  /// The line shown under the chart while this point is selected.
  final String detail;
}

/// A popularity × profitability matrix: four quadrants, two threshold lines,
/// one dot per dish.
///
/// Hand-drawn rather than handed to fl_chart, for the same reason [RankedBars]
/// is (see charts.dart). The whole point of this picture is the crosshair — a
/// dish means nothing at an absolute position and everything relative to the
/// two thresholds — and fl_chart's `ScatterChart` does not draw
/// `extraLinesData` at all, so the lines that carry the meaning are the one
/// thing it cannot put on the page. What is left is a box, two rules and some
/// positioned circles, which is less code than fighting a chart library's
/// gutter arithmetic for the right to draw them.
///
/// The quadrants are shaded as a faint checkerboard rather than in four
/// colours. Colour is already doing a job here — each dot is coloured by its
/// class — and a second colour system behind it would fight the first.
class QuadrantScatter extends StatefulWidget {
  const QuadrantScatter({
    required this.points,
    required this.xThreshold,
    required this.yThreshold,
    required this.xAxisLabel,
    required this.yAxisLabel,
    required this.quadrantLabels,
    required this.formatX,
    required this.formatY,
    this.height = 300,
    super.key,
  });

  final List<QuadrantPoint> points;

  /// Where the vertical rule goes: the share of units a dish must clear to
  /// count as popular.
  final double xThreshold;

  /// Where the horizontal rule goes: the average contribution margin per unit.
  final double yThreshold;

  final String xAxisLabel;
  final String yAxisLabel;

  /// Corner captions, in reading order: top-left, top-right, bottom-left,
  /// bottom-right.
  final ({String topLeft, String topRight, String bottomLeft, String bottomRight})
      quadrantLabels;

  final String Function(double value) formatX;
  final String Function(double value) formatY;

  final double height;

  /// The plot box itself, so a test can measure a dot against the rectangle it
  /// is supposed to sit inside. `find.byType(CustomPaint)` cannot: Material
  /// draws with several of its own.
  static const Key plotKey = Key('quadrant-scatter-plot');

  @override
  State<QuadrantScatter> createState() => _QuadrantScatterState();
}

class _QuadrantScatterState extends State<QuadrantScatter> {
  int? _selected;

  /// Radius of a dot. Not scaled with the text: forty dishes at a 2x font would
  /// be one continuous blob, and the size of a dot is not something anybody
  /// reads.
  static const double _dot = 5;

  /// How near a tap has to land. Generous, because dots overlap and the nearest
  /// one is almost always the one meant.
  static const double _tapSlop = 32;

  @override
  void didUpdateWidget(QuadrantScatter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The period can change under a selection — dropping it is right, because
    // index 3 in the old list is a different dish in the new one.
    if (oldWidget.points != widget.points) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final bounds = _Bounds.of(
      points: widget.points,
      xThreshold: widget.xThreshold,
      yThreshold: widget.yThreshold,
    );

    // The axis gutters hold text, so they grow with the reader's font. Capped:
    // past about 2x the plot is being eaten faster than the labels are helped.
    final leftGutter = scaledForText(context, 52, cap: 2.0);
    final bottomGutter = scaledForText(context, 22, cap: 2.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: leftGutter,
              height: widget.height,
              child: _VerticalAxis(
                bounds: bounds,
                format: widget.formatY,
                style: small,
              ),
            ),
            Expanded(
              child: SizedBox(
                height: widget.height,
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) => _selectNearest(
                      details.localPosition,
                      constraints.biggest,
                      bounds,
                    ),
                    child: Stack(
                      key: QuadrantScatter.plotKey,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _MatrixPainter(
                              bounds: bounds,
                              scheme: scheme,
                            ),
                          ),
                        ),
                        ..._quadrantCaptions(context, bounds, small),
                        ..._dots(constraints.biggest, bounds, scheme),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: bottomGutter - 14),
        Padding(
          padding: EdgeInsets.only(left: leftGutter),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.formatX(bounds.minX), style: small),
              Text(widget.xAxisLabel, style: small),
              Text(widget.formatX(bounds.maxX), style: small),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SelectedDetail(
          point: _selected == null ? null : widget.points[_selected!],
          placeholder: widget.points.isEmpty
              ? 'Nothing to place yet.'
              : 'Tap a dot to see which dish it is.',
        ),
      ],
    );
  }

  List<Widget> _quadrantCaptions(
    BuildContext context,
    _Bounds bounds,
    TextStyle? style,
  ) {
    final faint = style?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(
            alpha: 0.75,
          ),
      fontWeight: FontWeight.w600,
    );
    const pad = EdgeInsets.all(6);
    final labels = widget.quadrantLabels;

    return [
      Align(
        alignment: Alignment.topLeft,
        child: Padding(padding: pad, child: Text(labels.topLeft, style: faint)),
      ),
      Align(
        alignment: Alignment.topRight,
        child: Padding(padding: pad, child: Text(labels.topRight, style: faint)),
      ),
      Align(
        alignment: Alignment.bottomLeft,
        child:
            Padding(padding: pad, child: Text(labels.bottomLeft, style: faint)),
      ),
      Align(
        alignment: Alignment.bottomRight,
        child:
            Padding(padding: pad, child: Text(labels.bottomRight, style: faint)),
      ),
    ];
  }

  List<Widget> _dots(Size size, _Bounds bounds, ColorScheme scheme) => [
        for (var i = 0; i < widget.points.length; i++)
          () {
            final point = widget.points[i];
            final offset = bounds.toPixels(point.x, point.y, size);
            final isSelected = _selected == i;
            final radius = isSelected ? _dot + 3 : _dot;
            return Positioned(
              left: offset.dx - radius,
              top: offset.dy - radius,
              width: radius * 2,
              height: radius * 2,
              child: Semantics(
                label: point.label,
                value: point.detail,
                button: true,
                selected: isSelected,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: point.color,
                    // A hairline in the surface colour so overlapping dots stay
                    // countable instead of merging into one shape.
                    border: Border.all(
                      color: isSelected ? scheme.onSurface : scheme.surface,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                ),
              ),
            );
          }(),
      ];

  void _selectNearest(Offset tap, Size size, _Bounds bounds) {
    int? nearest;
    var best = double.infinity;
    for (var i = 0; i < widget.points.length; i++) {
      final point = widget.points[i];
      final distance =
          (bounds.toPixels(point.x, point.y, size) - tap).distance;
      if (distance < best) {
        best = distance;
        nearest = i;
      }
    }
    if (nearest == null || best > _tapSlop) {
      // Tapping the empty plot clears, rather than leaving a stale dish named
      // under a chart the reader has moved on from.
      if (_selected != null) setState(() => _selected = null);
      return;
    }
    setState(() => _selected = _selected == nearest ? null : nearest);
  }
}

/// The plot's extents, and the one place that turns a value into a position.
class _Bounds {
  const _Bounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.xThreshold,
    required this.yThreshold,
  });

  final double minX, maxX, minY, maxY, xThreshold, yThreshold;

  factory _Bounds.of({
    required List<QuadrantPoint> points,
    required double xThreshold,
    required double yThreshold,
  }) {
    // The thresholds are always inside the plot even when no dish is near them
    // — a crosshair drawn off the edge is worse than an empty quadrant, because
    // it silently stops being the thing the four corners are named after.
    var minX = xThreshold, maxX = xThreshold;
    var minY = yThreshold, maxY = yThreshold;
    for (final point in points) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }

    // A share cannot be negative, and starting the axis at zero keeps the
    // distances between dishes honest.
    minX = 0;

    return _Bounds(
      minX: minX,
      maxX: _padded(minX, maxX),
      minY: minY == maxY ? minY - 1 : minY - (maxY - minY) * 0.12,
      maxY: _padded(minY, maxY),
      xThreshold: xThreshold,
      yThreshold: yThreshold,
    );
  }

  /// Headroom so a dot at the extreme is not drawn half outside the box, and a
  /// floor so a single dish does not divide by a zero-width range.
  static double _padded(double min, double max) =>
      min == max ? max + 1 : max + (max - min) * 0.12;

  double get _spanX => maxX - minX;
  double get _spanY => maxY - minY;

  Offset toPixels(double x, double y, Size size) => Offset(
        (x - minX) / _spanX * size.width,
        // Screens count downward and margins count upward.
        (1 - (y - minY) / _spanY) * size.height,
      );

  double xLineAt(double width) => (xThreshold - minX) / _spanX * width;
  double yLineAt(double height) =>
      (1 - (yThreshold - minY) / _spanY) * height;
}

/// The tints, the border and the crosshair. Everything under the dots.
class _MatrixPainter extends CustomPainter {
  const _MatrixPainter({required this.bounds, required this.scheme});

  final _Bounds bounds;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final x = bounds.xLineAt(size.width);
    final y = bounds.yLineAt(size.height);

    // A checkerboard, so the four cells read as four cells without needing four
    // colours — colour here would compete with the dots, which are already
    // coloured by class and are the thing being read. Faint enough to be paper
    // rather than ink.
    final wash = Paint()..color = scheme.surfaceContainerHighest.withValues(
        alpha: 0.55,
      );
    canvas.drawRect(Rect.fromLTRB(0, 0, x, y), wash);
    canvas.drawRect(Rect.fromLTRB(x, y, size.width, size.height), wash);

    final border = Paint()
      ..color = scheme.outlineVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, border);

    final rule = Paint()
      ..color = scheme.outline
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), rule);
    canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
  }

  @override
  bool shouldRepaint(_MatrixPainter old) =>
      old.bounds != bounds || old.scheme != scheme;
}

/// The y axis: the two ends and the threshold, and nothing in between.
///
/// Ticks at regular intervals would be noise here. The only vertical position
/// that means anything is the average margin, so that is what gets a number.
class _VerticalAxis extends StatelessWidget {
  const _VerticalAxis({
    required this.bounds,
    required this.format,
    required this.style,
  });

  final _Bounds bounds;
  final String Function(double) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final thresholdY = bounds.yLineAt(height);
          return Stack(
            children: [
              Positioned(
                top: 0,
                right: 6,
                child: Text(format(bounds.maxY), style: style),
              ),
              Positioned(
                // Centred on the rule, and kept inside the box at both ends so
                // it cannot be clipped by the edge of the chart.
                top: (thresholdY - 8).clamp(0.0, height - 16),
                right: 6,
                child: Text(
                  format(bounds.yThreshold),
                  style: style?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 6,
                child: Text(format(bounds.minY), style: style),
              ),
            ],
          );
        },
      );
}

/// The line under the chart naming whichever dot was last tapped.
///
/// A fixed row rather than a floating tooltip: on a phone a tooltip over a
/// crowded corner covers the dots it is describing, and this has somewhere to
/// put a name too long to fit beside a dot.
class _SelectedDetail extends StatelessWidget {
  const _SelectedDetail({required this.point, required this.placeholder});

  final QuadrantPoint? point;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = point;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: selected == null
          ? Text(
              placeholder,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected.color,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selected.label,
                          style: theme.textTheme.titleSmall),
                      Text(
                        selected.detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
