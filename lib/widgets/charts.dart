import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

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

    return _ChartFrame(
      title: title,
      child: SizedBox(
        height: height,
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
                  reservedSize: 44,
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
                  reservedSize: 28,
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
                        offset: const Offset(0, -10),
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
      child: Column(
        children: [
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      point.label,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: point.value / highest,
                        minHeight: 18,
                        backgroundColor: scheme.surfaceContainerHighest,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: Text(
                      format(point.value),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
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
