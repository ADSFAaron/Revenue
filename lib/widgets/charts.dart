import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'text_scale.dart';

/// One labelled value on a chart.
class ChartPoint {
  const ChartPoint({required this.label, required this.value});

  /// What goes under the column, or beside the bar. A date, an hour, a dish.
  final String label;

  final num value;
}

/// A column chart with the app's own colours on it.
///
/// Replaces the Syncfusion equivalent, which was fine to look at and came with
/// a licence condition on the *organisation* — free only under a million
/// dollars of revenue and under five developers, which can stop being true
/// without anybody touching a line of this. There is nothing first-party to
/// move to instead; Google archived `charts_flutter` in January 2023.
///
/// Deliberately plain. A shop reads these to answer "when was it busy" and
/// "was yesterday normal", and both are shape questions — the picture does the
/// work and the decoration gets in its way.
class ColumnChart extends StatelessWidget {
  const ColumnChart({
    required this.title,
    required this.points,
    this.height = 260,
    this.formatValue,
    super.key,
  });

  final String title;
  final List<ChartPoint> points;
  final double height;

  /// For the tooltip and the number over a column. Defaults to the plain value.
  final String Function(num value)? formatValue;

  /// Above this many columns, the numbers over them stop being readable and
  /// start being a grey smear. The tooltip covers that case.
  static const int _labelsUpTo = 12;

  /// How many x labels a phone can carry before they collide. Beyond it, every
  /// nth label is drawn — chosen over rotating all of them, because a row of
  /// forty-five-degree dates is a texture rather than an axis.
  static const int _maxAxisLabels = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small =
        theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final format = formatValue ?? (value) => '$value';

    if (points.isEmpty) {
      return _ChartFrame(
        title: title,
        child: SizedBox(
          height: 96,
          child: Center(
            child: Text('Nothing to chart yet.', style: small),
          ),
        ),
      );
    }

    var highest = 0.0;
    for (final point in points) {
      if (point.value > highest) highest = point.value.toDouble();
    }
    // Headroom so a full-height column does not have its own label clipped by
    // the top of the plot, and a floor so an all-zero day draws an axis rather
    // than a division by nothing.
    final maxY = highest <= 0 ? 1.0 : highest * 1.18;
    final every = (points.length / _maxAxisLabels).ceil().clamp(1, 999);

    // fl_chart reserves the axis gutters as plain numbers and clips whatever
    // does not fit, so a phone on a large system font lost the bottom row of
    // dates entirely. The plot keeps its own height; the extra the labels need
    // is added to the box rather than taken out of the columns.
    final leftGutter = scaledForText(context, 44, cap: 2.0);
    final bottomGutter = scaledForText(context, 28, cap: 2.0);

    return _ChartFrame(
      title: title,
      child: SizedBox(
        height: height + bottomGutter - 28,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: scheme.outlineVariant, strokeWidth: 1),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: leftGutter,
                  getTitlesWidget: (value, meta) =>
                      value == meta.max || value < 0
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(meta.formattedValue,
                                  style: small, textAlign: TextAlign.right),
                            ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: bottomGutter,
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index < 0 || index >= points.length) {
                      return const SizedBox.shrink();
                    }
                    if (index % every != 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(points[index].label, style: small),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                    BarTooltipItem(
                  '${points[group.x].label}\n',
                  theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onInverseSurface) ??
                      const TextStyle(),
                  children: [
                    TextSpan(
                      text: format(points[group.x].value),
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: scheme.onInverseSurface),
                    ),
                  ],
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < points.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: points[i].value.toDouble(),
                      color: scheme.primary,
                      width: points.length > 20 ? 6 : 14,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                      label: BarChartRodLabel(
                        show: points.length <= _labelsUpTo &&
                            points[i].value != 0,
                        text: format(points[i].value),
                        style: small,
                        // Positive dy lifts the label clear of the tip:
                        // fl_chart draws it at `tip - dy - textHeight`. This
                        // was -10, which pushed it *down* by ten and printed
                        // the takings across the top of their own column.
                        offset: const Offset(0, 6),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A ranked list as horizontal bars — best sellers, and anything else where the
/// order is the message.
///
/// Not a chart library at all, and on purpose. A horizontal bar chart with
/// categorical labels is the one shape charting packages handle worst: the
/// names here are long, frequently Chinese, and want to sit flat and
/// left-aligned next to their bar rather than be squeezed under it or turned on
/// their side. A row with a name, a proportional box and a number is the whole
/// widget, and it wraps, scales and themes like the rest of the app because it
/// is made of the same things.
class RankedBars extends StatelessWidget {
  const RankedBars({
    required this.title,
    required this.points,
    this.formatValue,
    super.key,
  });

  final String title;
  final List<ChartPoint> points;
  final String Function(num value)? formatValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = formatValue ?? (num value) => '$value';

    if (points.isEmpty) return const SizedBox.shrink();

    var highest = 0.0;
    for (final point in points) {
      if (point.value > highest) highest = point.value.toDouble();
    }
    if (highest <= 0) highest = 1;

    return _ChartFrame(
      title: title,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidth = scaledForText(context, 120, cap: 1.5);
          // At a large system font the name column eats the row it is meant
          // to label, and the bar between it and the figure is squeezed to
          // nothing. Past that point the name goes on its own line and the
          // bar gets the width back, which is the same answer as a narrow
          // window — it just arrives through the font size instead.
          final stacked = labelWidth > constraints.maxWidth * 0.4;

          Widget bar(ChartPoint point) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: point.value / highest,
                  minHeight: 18,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: scheme.primary,
                ),
              );

          Widget figure(ChartPoint point) => Text(
                format(point.value),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final point in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(point.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(child: bar(point)),
                                const SizedBox(width: 8),
                                figure(point),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            SizedBox(
                              width: labelWidth,
                              child: Text(
                                point.label,
                                textAlign: TextAlign.right,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: bar(point)),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              // A minimum rather than a width: the figures
                              // line up in the ordinary case, and a longer
                              // one takes the room it needs instead of
                              // wrapping inside 44pt.
                              constraints:
                                  const BoxConstraints(minWidth: 44),
                              child: figure(point),
                            ),
                          ],
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A title over a picture, the same distance away every time.
class _ChartFrame extends StatelessWidget {
  const _ChartFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      );
}
