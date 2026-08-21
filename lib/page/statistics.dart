import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import '../database/repositories.dart';
import '../models/daily_stats.dart';

// Phase 3 of docs/refactor-plan.md still owes this page:
//   - Week / Month tabs over real date ranges (they currently show the day)
//   - working back / forward arrows
//   - Excel export (Phase 5)
// The data layer for all three is already in place: StatsRepository.fetchRange
// plus DailyStats.sum give a summed range in one call.

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage>
    with TickerProviderStateMixin {
  late final Future<Session> _session = loadSession();
  late final TabController _tabController;

  bool isDark = false;
  int _selectedTabIndex = 0;

  Map<String, bool> featureSelected = {
    'Income': false,
    'Export': false,
  };

  static const List<Tab> myTabs = <Tab>[
    Tab(text: 'Day'),
    Tab(text: 'Week'),
    Tab(text: 'Month'),
  ];

  TooltipBehavior? _tooltipBehavior;

  @override
  void initState() {
    super.initState();
    _tooltipBehavior = TooltipBehavior(
      enable: true,
      header: '',
      canShowMarker: false,
    );
    _tabController = TabController(length: myTabs.length, vsync: this);
    _tabController.addListener(() {
      setState(() => _selectedTabIndex = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const String assetName = 'assets/google-gemini-icon.svg';
    final Widget svg = SvgPicture.asset(
      assetName,
      semanticsLabel: 'Gemini Logo',
      height: 24,
      width: 24,
      colorFilter: isDark
          ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
          : const ColorFilter.mode(Colors.black, BlendMode.srcIn),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        bottom: TabBar(controller: _tabController, tabs: myTabs),
      ),
      body: FutureBuilder<Session>(
        future: _session,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final session = snapshot.data!;
          final businessDate = session.store.currentBusinessDate;

          // One rollup document instead of the store's entire order history.
          return StreamBuilder<DailyStats>(
            stream: statsRepository.watchDay(session.storeId, businessDate),
            builder: (context, statsSnapshot) {
              if (statsSnapshot.hasError) {
                return Center(child: Text('Error: ${statsSnapshot.error}'));
              }
              if (!statsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return _buildContent(session, statsSnapshot.data!);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => debugPrint('FloatingActionButton tapped'),
        child: GestureDetector(child: svg),
      ),
    );
  }

  Widget _buildContent(Session session, DailyStats stats) {
    if (stats.isEmpty) {
      return SafeArea(
        child: Column(
          children: [
            _buildHeaderRow(stats.businessDate),
            const Expanded(child: Center(child: Text('No Order'))),
          ],
        ),
      );
    }

    // Every tab shows the same trading day until the Week / Month ranges land
    // in Phase 3 — one body rather than three copies of it.
    final body = _buildTabBody(session, stats);
    return SafeArea(
      child: TabBarView(
        controller: _tabController,
        children: [body, body, body],
      ),
    );
  }

  Widget _buildTabBody(Session session, DailyStats stats) {
    final chartData = stats.itemsByQty
        .map((item) => ChartSampleData(x: item.name, yValue: item.qty))
        .toList();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          spacing: 20,
          children: <Widget>[
            _buildHeaderRow(stats.businessDate),
            // Target comes from the store's settings, not from a literal 60/200.
            _buildRangePointerGauge(
              stats.orderCount,
              session.store.targets.dailyOrders,
            ),
            _buildCartesianChart("Today's Dishes", chartData),
            Wrap(
              children: [
                if (featureSelected['Income']!)
                  _buildCard(
                    title: 'Income',
                    icon: Symbols.money_bag,
                    value: NumberFormat.decimalPattern().format(stats.revenue),
                    onTap: () => debugPrint('money Card tapped'),
                  ),
                if (featureSelected['Export']!)
                  _buildCard(
                    title: 'Export',
                    icon: Icons.download_outlined,
                    value: 'Excel',
                    onTap: () => debugPrint('excel tapped'),
                  ),
                _buildAddMoreCard(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(String businessDate) {
    final infoDate = DateTime.tryParse(businessDate) ?? DateTime.now();
    final now = DateTime.now();
    String displayDate;

    switch (_selectedTabIndex) {
      case 1:
        displayDate = 'Week ${infoDate.weekOfYear} of ${infoDate.year}';
        break;
      case 2:
        displayDate = DateFormat.yMMMM().format(infoDate);
        break;
      default:
        if (infoDate.year == now.year &&
            infoDate.month == now.month &&
            infoDate.day == now.day) {
          displayDate = 'Today';
        } else {
          displayDate = DateFormat.yMMMMd().format(infoDate);
        }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Paging through past periods is Phase 3; disabled rather than silently
        // doing nothing when tapped.
        ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(elevation: 0),
          child: const Icon(Icons.arrow_back),
        ),
        Text(displayDate, style: const TextStyle(fontSize: 20)),
        ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(elevation: 0),
          child: const Icon(Icons.arrow_forward),
        ),
      ],
    );
  }

  Widget _buildAddMoreCard(BuildContext context) {
    return Card(
      elevation: 0,
      child: InkWell(
        onTap: () => showModalBottomSheet(
          context: context,
          builder: (context) => _buildAddMoreSheet(context),
        ),
        child: SizedBox(
          width: MediaQuery.of(context).size.width / 2 - 30,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).splashColor,
                    borderRadius: BorderRadius.circular(48),
                  ),
                  height: 48,
                  width: 48,
                  child:
                      Icon(Icons.add, color: Theme.of(context).iconTheme.color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddMoreSheet(BuildContext context) {
    Widget toggle(String key, String subtitle) => ListTile(
          leading: Icon(featureSelected[key]!
              ? Icons.check_box_outlined
              : Icons.check_box_outline_blank),
          title: Text(key),
          subtitle: Text(subtitle),
          onTap: () {
            setState(() => featureSelected[key] = !featureSelected[key]!);
            Navigator.pop(context);
          },
        );

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.3,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('More Feature', style: TextStyle(fontSize: 20)),
              toggle('Income', 'Selected Date Income'),
              toggle('Export', 'Export data to Excel'),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Return the Cartesian Chart with Column series.
  SfCartesianChart _buildCartesianChart(
      String chartTitle, List<ChartSampleData> data) {
    num max = 0;
    for (final point in data) {
      if ((point.yValue ?? 0) > max) max = point.yValue!;
    }

    return SfCartesianChart(
      plotAreaBorderWidth: 0,
      title: ChartTitle(text: chartTitle),
      primaryXAxis: const CategoryAxis(
        majorGridLines: MajorGridLines(width: 0),
      ),
      primaryYAxis: NumericAxis(
        minimum: 0,
        maximum: max.toDouble() == 0 ? 1 : max.toDouble(),
        isVisible: true,
        labelFormat: '{value}',
      ),
      series: _buildColumnSeries(data),
      tooltipBehavior: _tooltipBehavior,
    );
  }

  /// Returns the list of Cartesian Column series.
  List<ColumnSeries<ChartSampleData, String>> _buildColumnSeries(
      List<ChartSampleData> source) {
    return <ColumnSeries<ChartSampleData, String>>[
      ColumnSeries<ChartSampleData, String>(
        dataSource: source,
        xValueMapper: (ChartSampleData data, int index) => data.x,
        yValueMapper: (ChartSampleData data, int index) => data.yValue,
        pointColorMapper: (ChartSampleData data, int index) => data.pointColor,
        dataLabelSettings: const DataLabelSettings(isVisible: true),
      ),
    ];
  }

  Widget _buildCard({
    required String title,
    String? value,
    IconData? icon,
    required VoidCallback onTap,
    double? growth,
  }) {
    Widget growthContainer = const SizedBox.shrink();

    if (growth != null) {
      final trendIcon = growth >= 0
          ? const Icon(Icons.trending_up_rounded, size: 16, color: Colors.green)
          : const Icon(Icons.trending_down_rounded,
              size: 16, color: Colors.red);

      growthContainer = Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: growth >= 0 ? Colors.green[100] : Colors.red[100],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            trendIcon,
            Text(
              ' $growth%',
              style: TextStyle(
                color: growth >= 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: MediaQuery.of(context).size.width / 2 - 30,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).splashColor,
                        borderRadius: BorderRadius.circular(48),
                      ),
                      height: 48,
                      width: 48,
                      child:
                          Icon(icon, color: Theme.of(context).iconTheme.color),
                    ),
                    const SizedBox(width: 10),
                    Flexible(child: Text(title)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        child: Text(value ?? '',
                            style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                    growth != null
                        ? const Spacer()
                        : const SizedBox(width: 8),
                    growthContainer,
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

///Chart sample data
class ChartSampleData {
  /// Holds the datapoint values like x, y, etc.,
  ChartSampleData({this.x, this.yValue, this.pointColor});

  /// Holds x value of the datapoint
  final dynamic x;

  /// Holds y value of the datapoint
  final num? yValue;

  /// Holds point color of the datapoint
  final Color? pointColor;
}

SfRadialGauge _buildRangePointerGauge(num currentOrders, num expectOrders) {
  final safeTarget = expectOrders <= 0 ? 1 : expectOrders;
  final ordersPercent = (currentOrders / safeTarget) * 100;

  return SfRadialGauge(
    axes: <RadialAxis>[
      RadialAxis(
        showLabels: true,
        showTicks: false,
        maximum: safeTarget.toDouble(),
        radiusFactor: 0.8,
        axisLineStyle: const AxisLineStyle(
          thicknessUnit: GaugeSizeUnit.factor,
          thickness: 0.15,
        ),
        annotations: <GaugeAnnotation>[
          GaugeAnnotation(
            angle: 200,
            widget: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '$currentOrders',
                      style: const TextStyle(
                        fontFamily: 'Times',
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      ' / $expectOrders',
                      style: const TextStyle(
                        fontFamily: 'Times',
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
                Text('${ordersPercent.toStringAsFixed(0)}%'),
              ],
            ),
          ),
        ],
        pointers: <GaugePointer>[
          RangePointer(
            value: currentOrders.toDouble().clamp(0, safeTarget.toDouble()),
            enableAnimation: true,
            animationDuration: 1000,
            sizeUnit: GaugeSizeUnit.factor,
            gradient: const SweepGradient(
              colors: <Color>[Color(0xFF6A6EF6), Color(0xFFDB82F5)],
              stops: <double>[0.25, 0.75],
            ),
            color: const Color(0xFF00A8B5),
            width: 0.15,
          ),
        ],
      ),
    ],
  );
}

extension DateTimeExtension on DateTime {
  int get weekOfYear {
    // Add 3 to the date to ensure it falls within the correct week
    DateTime date = add(const Duration(days: 3));
    int dayOfYear = int.parse(DateFormat("D").format(date));
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }

  int get weekOfMonth => (day / 7).ceil();
}
