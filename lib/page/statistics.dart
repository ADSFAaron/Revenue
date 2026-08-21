import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import '../database/repositories.dart';
import '../export/statistics_workbook.dart';
import '../export/workbook_saver.dart';
import '../models/daily_stats.dart';
import '../models/stats_period.dart';
import '../models/store.dart';
import 'analysis.dart';

// The Gemini button (F7) is still unwired.

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  Session? _session;
  Object? _sessionError;

  /// The span on screen. Null only until the session resolves, because the
  /// store's cutoff hour decides which trading day "today" is.
  StatsPeriod? _period;

  /// Rebuilt in lockstep with [_period] rather than in `build`, so that a
  /// rebuild for any other reason does not tear down the subscription and pay
  /// for the same documents again.
  Stream<PeriodReport>? _reportStream;

  bool isDark = false;
  bool _exporting = false;

  Map<String, bool> featureSelected = {
    'Income': false,
    'Export': false,
  };

  TooltipBehavior? _tooltipBehavior;

  @override
  void initState() {
    super.initState();
    _tooltipBehavior = TooltipBehavior(
      enable: true,
      header: '',
      canShowMarker: false,
    );
    _tabController =
        TabController(length: StatsGranularity.values.length, vsync: this)
          ..addListener(_onTabChanged);

    loadSession().then((session) {
      if (!mounted) return;
      setState(() {
        _session = session;
        _setPeriod(StatsPeriod.current(session.store, StatsGranularity.day));
      });
    }).catchError((Object error) {
      if (mounted) setState(() => _sessionError = error);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// The trading day the store is currently in — not `DateTime.now()`, which
  /// before the cutoff hour still belongs to yesterday's takings.
  DateTime get _today => parseBusinessDate(_session!.store.currentBusinessDate);

  /// Assigns the period and the stream that serves it. Must be called from
  /// inside a `setState`.
  void _setPeriod(StatsPeriod period) {
    _period = period;
    _reportStream = statsRepository
        .watchPeriod(_session!.storeId, period, today: _today)
        .asBroadcastStream();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging || _period == null) return;
    final granularity = StatsGranularity.values[_tabController.index];
    if (granularity == _period!.granularity) return;
    // Keeps where you are in time: paging back to June and then switching to
    // Day lands on a day in June rather than jumping back to today.
    setState(() => _setPeriod(_period!.withGranularity(granularity)));
  }

  /// Writes the period on screen out as a spreadsheet.
  ///
  /// Encoding a workbook is slow enough to be noticed, so the card is latched
  /// while it runs — tapping twice would otherwise start a second export and
  /// hand back two files.
  Future<void> _export(Session session, PeriodReport report) async {
    setState(() => _exporting = true);
    try {
      final workbook = StatisticsWorkbook(
        store: session.store,
        period: report.period,
        days: report.days,
      );
      final outcome = await saveWorkbook(
        excel: workbook.build(),
        fileName: workbook.fileName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(outcome.description)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Export failed: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _step(int direction) {
    setState(() =>
        _setPeriod(direction < 0 ? _period!.previous : _period!.next));
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
        actions: [
          IconButton(
            icon: const Icon(Icons.insights_rounded),
            tooltip: 'Insights',
            // Only once the session is in hand: every report behind here needs
            // the store's cutoff hour to know which days it is looking at.
            onPressed: _session == null
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AnalysisPage(session: _session!),
                    )),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            for (final granularity in StatsGranularity.values)
              Tab(text: granularity.label),
          ],
        ),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => debugPrint('FloatingActionButton tapped'),
        child: GestureDetector(child: svg),
      ),
    );
  }

  Widget _buildBody() {
    if (_sessionError != null) {
      return Center(child: Text('Error: $_sessionError'));
    }
    if (_session == null || _period == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final session = _session!;
    final period = _period!;

    // The three tabs share one body rather than sitting in a TabBarView. A
    // TabBarView keeps every visited tab alive, so a glance at Week and Month
    // would leave three live range subscriptions running against Firestore for
    // the rest of the visit.
    return SafeArea(
      child: Column(
        children: [
          // Outside the StreamBuilder: the arrows have to keep working while a
          // period loads, and above all on an empty period, which is otherwise
          // a dead end you cannot page out of.
          _buildHeaderRow(period),
          Expanded(
            child: StreamBuilder<PeriodReport>(
              stream: _reportStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final report = snapshot.data!;
                if (report.isEmpty) {
                  return Center(
                    child: Text('No orders in ${period.label(_today)}'),
                  );
                }
                return _buildReport(session, report);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(StatsPeriod period) {
    // Nothing has been rung up in the future, so there is nothing to page
    // forward into once the period on screen contains today.
    final atPresent = period.contains(_today);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton(
            onPressed: () => _step(-1),
            style: ElevatedButton.styleFrom(elevation: 0),
            child: const Icon(Icons.arrow_back),
          ),
          Flexible(
            child: Text(
              period.label(_today),
              style: const TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ElevatedButton(
            onPressed: atPresent ? null : () => _step(1),
            style: ElevatedButton.styleFrom(elevation: 0),
            child: const Icon(Icons.arrow_forward),
          ),
        ],
      ),
    );
  }

  Widget _buildReport(Session session, PeriodReport report) {
    final period = report.period;
    final total = report.total;
    final previous = report.previousTotal;
    final money = _moneyFormat(session.store);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          spacing: 20,
          children: <Widget>[
            Wrap(
              children: [
                _buildCard(
                  title: 'Revenue',
                  icon: Symbols.money_bag,
                  value: money.format(total.revenue),
                  change: PeriodReport.change(total.revenue, previous.revenue),
                ),
                _buildCard(
                  title: 'Orders',
                  icon: Icons.receipt_long_outlined,
                  value: NumberFormat.decimalPattern().format(total.orderCount),
                  change: PeriodReport.change(
                      total.orderCount, previous.orderCount),
                ),
                _buildCard(
                  title: 'Gross profit',
                  icon: Icons.trending_up_rounded,
                  value: money.format(total.grossProfit),
                  change: PeriodReport.change(
                      total.grossProfit, previous.grossProfit),
                ),
                _buildCard(
                  title: 'Per head',
                  icon: Icons.groups_outlined,
                  value: money.format(total.averageGuestSpend.round()),
                  change: PeriodReport.change(
                      total.averageGuestSpend, previous.averageGuestSpend),
                ),
              ],
            ),
            Text(
              period.comparisonLabel(_today),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            _buildTargetGauge(session.store, period, total),
            _buildTrendChart(session.store, report),
            _buildTopDishesChart(total),
            Wrap(
              children: [
                if (featureSelected['Income']!)
                  _buildCard(
                    title: 'Income',
                    icon: Symbols.money_bag,
                    value: money.format(total.revenue),
                    onTap: () => debugPrint('money Card tapped'),
                  ),
                if (featureSelected['Export']!)
                  _buildCard(
                    title: 'Export',
                    icon: _exporting
                        ? Icons.hourglass_top_rounded
                        : Icons.download_outlined,
                    value: 'Excel',
                    // Exports exactly the period on screen, so what lands in
                    // the file is what the page is showing.
                    onTap: _exporting ? null : () => _export(session, report),
                  ),
                _buildAddMoreCard(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Progress against the store's daily order target.
  ///
  /// Over a week or a month the target is scaled to the days that have actually
  /// happened, not to the whole period: two days into a month, 60 orders is on
  /// track, and measuring it against thirty days' worth of target would report
  /// it as a 6% failure.
  Widget _buildTargetGauge(
      Store store, StatsPeriod period, DailyStats total) {
    final elapsed = period.elapsedDays(_today).clamp(1, period.dayCount);
    return _buildRangePointerGauge(
      total.orderCount,
      store.targets.dailyOrders * elapsed,
    );
  }

  /// How the takings moved inside the period: by hour for a single day, by
  /// trading day for a week or a month.
  Widget _buildTrendChart(Store store, PeriodReport report) {
    final period = report.period;

    if (period.granularity == StatsGranularity.day) {
      return _buildCartesianChart(
        'Revenue by hour',
        _hourlyData(report.total),
      );
    }

    // Days with no takings have no document at all, so they are filled back in
    // here — a chart that silently skips the days a shop was closed makes a
    // four-day week look like a full one.
    final byDate = {for (final day in report.days) day.businessDate: day};
    final data = <ChartSampleData>[];
    for (var offset = 0; offset < period.dayCount; offset++) {
      final date =
          DateTime(period.start.year, period.start.month, period.start.day + offset);
      if (date.isAfter(_today)) break;
      data.add(ChartSampleData(
        x: DateFormat.Md().format(date),
        yValue: byDate[formatBusinessDate(date)]?.revenue ?? 0,
      ));
    }
    return _buildCartesianChart('Revenue by day', data);
  }

  /// Hours from the first sale of the day to the last, gaps included, so a
  /// lunchtime peak and a quiet mid-afternoon keep their real shape.
  List<ChartSampleData> _hourlyData(DailyStats total) {
    final hours = total.byHour.keys
        .map(int.tryParse)
        .whereType<int>()
        .toList()
      ..sort();
    if (hours.isEmpty) return const [];

    return [
      for (var hour = hours.first; hour <= hours.last; hour++)
        ChartSampleData(
          x: '${hour.toString().padLeft(2, '0')}:00',
          yValue: total.byHour['$hour']?.revenue ?? 0,
        ),
    ];
  }

  /// Best sellers by units. Capped, because a month can span the whole menu and
  /// forty columns on a phone are unreadable.
  Widget _buildTopDishesChart(DailyStats total) {
    final data = total.itemsByQty
        .take(10)
        .map((item) => ChartSampleData(x: item.name, yValue: item.qty))
        .toList();
    return _buildCartesianChart('Top dishes', data);
  }

  NumberFormat _moneyFormat(Store store) => NumberFormat.currency(
        // Firestore holds money as whole units — see the schema notes in
        // docs/refactor-plan.md — so a decimal place would only ever show '.00'.
        name: store.currency,
        symbol: store.currency == 'TWD' ? 'NT\$' : null,
        decimalDigits: 0,
      );

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
        labelIntersectAction: AxisLabelIntersectAction.rotate45,
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
    VoidCallback? onTap,
    double? change,
  }) {
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
                    const SizedBox(width: 8),
                    _ChangeBadge(change: change),
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

/// The "+12%" pill next to a figure.
///
/// A null [change] renders as an em dash rather than as 0%: "no comparison
/// available" and "flat against last month" are different things, and a shop's
/// first week would otherwise read as though it had gone nowhere.
class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({this.change});

  final double? change;

  @override
  Widget build(BuildContext context) {
    final change = this.change;
    if (change == null) {
      return Text('—', style: Theme.of(context).textTheme.bodySmall);
    }

    final rising = change >= 0;
    final color = rising ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: rising ? Colors.green[100] : Colors.red[100],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(rising ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 16, color: color),
          Text(
            ' ${(change * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
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
                      ' / $safeTarget',
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
