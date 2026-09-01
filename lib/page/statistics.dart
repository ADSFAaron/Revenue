import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import '../database/repositories.dart';
import '../export/statistics_workbook.dart';
import '../export/workbook_saver.dart';
import '../models/daily_stats.dart';
import '../models/stats_period.dart';
import '../models/store.dart';
import '../settings/user_manual.dart';
import '../widgets/charts.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';
import '../widgets/page_body.dart';
import '../widgets/stat_card.dart';
import 'addorder.dart';

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

  /// The most recent report off [_reportStream].
  ///
  /// Export moved to the app bar, which sits outside the `StreamBuilder` that
  /// holds the report, so the page has to keep hold of it. Reading it back off
  /// the stream instead would mean waiting for Firestore's *next* snapshot —
  /// on an idle shop, indefinitely.
  PeriodReport? _latestReport;
  StreamSubscription<PeriodReport>? _reportSub;

  bool _exporting = false;

  @override
  void initState() {
    super.initState();
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
    _reportSub?.cancel();
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
    _latestReport = null;
    _reportStream = statsRepository
        .watchPeriod(_session!.storeId, period, today: _today)
        .asBroadcastStream();

    _reportSub?.cancel();
    _reportSub = _reportStream!.listen(
      (report) {
        final wasExportable = _latestReport?.isEmpty == false;
        _latestReport = report;
        // Only when the app bar's export button has to change state — the
        // StreamBuilder below redraws the body on its own, and rebuilding the
        // whole page on every snapshot would do that work twice.
        if (wasExportable != !report.isEmpty && mounted) setState(() {});
      },
      // Two things go wrong without this, and the StreamBuilder below hides
      // neither of them by handling `hasError` itself.
      //
      // The subscription is a *second* listener on the same broadcast stream,
      // and a listener with no `onError` rethrows into the zone — so a refused
      // query put a real unhandled async error next to the tidy ErrorView, red
      // screen in debug and crash-log noise in release.
      //
      // Worse, [_latestReport] kept the last good report, so the app bar's
      // export button stayed lit over a body that was showing a failure, and
      // "export what is on screen" would have written out a period that is not
      // on screen. Dropping it puts the button back in step with the body.
      onError: (Object error) {
        _latestReport = null;
        if (mounted) setState(() {});
      },
    );
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
  /// Exports whatever the page is currently showing.
  Future<void> _exportCurrent() {
    final session = _session;
    final report = _latestReport;
    if (session == null || report == null || report.isEmpty) {
      return Future.value();
    }
    return _export(session, report);
  }

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
      showInfo(context, outcome.description);
    } catch (error) {
      if (!mounted) return;
      // Deliberately raw, unlike every other failure in the app. Nothing here
      // touches Firestore, so `describeFailure` has no mapping for what
      // actually goes wrong — a `StateError` out of the encoder, or a
      // `FileSystemException` — and would flatten all of it to "Something went
      // wrong". "No space left on device" is the sentence that tells somebody
      // what to do, and it only exists in the raw message.
      showError(context, 'Export failed: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Back to the period containing today, however far away it is.
  void _jumpToPresent() {
    setState(() =>
        _setPeriod(StatsPeriod.current(_session!.store, _period!.granularity)));
  }

  void _step(int direction) {
    setState(
        () => _setPeriod(direction < 0 ? _period!.previous : _period!.next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'How these figures are worked out',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const UserManual(initialTopic: ManualTopic.money),
              ),
            ),
          ),
          // Was three taps and two scrolls down: an unlabelled "+" card at the
          // foot of the page opened a sheet, ticking Export there closed the
          // sheet, and the export card then appeared back at the foot. The
          // selection also lived in memory only, so it was gone on the next
          // visit.
          IconButton(
            tooltip: 'Export to Excel',
            icon: _exporting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            onPressed: _exporting || _latestReport?.isEmpty != false
                ? null
                : _exportCurrent,
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
    );
  }

  Widget _buildBody() {
    if (_sessionError != null) {
      return ErrorView(_sessionError!);
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
          // The tabs share a body rather than sitting in a TabBarView (see
          // above), which also took the swipe gesture away. This puts paging
          // through time on it instead, which is the more useful of the two:
          // the tabs are three taps, the periods are unbounded.
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity.abs() < 200) return;
                if (velocity < 0) {
                  if (!period.contains(_today)) _step(1);
                } else {
                  _step(-1);
                }
              },
              child: StreamBuilder<PeriodReport>(
                stream: _reportStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return ErrorView(
                      snapshot.error!,
                      onRetry: () => setState(() => _setPeriod(period)),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final report = snapshot.data!;
                  if (report.isEmpty) {
                    // Reached constantly — every closed day the arrows page
                    // through lands here — and it used to be one sentence with
                    // nowhere to go.
                    return _EmptyPeriod(
                      label: period.label(_today),
                      atPresent: period.contains(_today),
                      storeId: session.storeId,
                    );
                  }
                  return _buildReport(session, report);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// True between midnight and the store's cutoff hour, when the trading day on
  /// screen still carries yesterday's date.
  ///
  /// This is the window in which a correct app looks broken: at 01:00 the
  /// phone says the 30th, "Today" holds the 29th's takings, and the only thing
  /// that explains the difference is a setting three screens away.
  bool get _beforeCutoff {
    final store = _session!.store;
    return store.dayCutoffHour > 0 &&
        store.currentBusinessDate != formatBusinessDate(DateTime.now());
  }

  Widget _buildHeaderRow(StatsPeriod period) {
    // Nothing has been rung up in the future, so there is nothing to page
    // forward into once the period on screen contains today.
    final atPresent = period.contains(_today);
    final theme = Theme.of(context);
    final cutoffHour = _session!.store.dayCutoffHour.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: PageBody(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filledTonal(
                  onPressed: () => _step(-1),
                  tooltip: 'Previous',
                  icon: const Icon(Icons.arrow_back),
                ),
                Flexible(
                  // Paging back a month and then wanting to be back at today meant
                  // thirty taps on the forward arrow. The label itself is the
                  // obvious place to put the way home.
                  child: Tooltip(
                    message: atPresent ? '' : 'Back to today',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: atPresent ? null : _jumpToPresent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    period.label(_today),
                                    style: theme.textTheme.titleLarge,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (!atPresent) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.today_outlined,
                                      size: 18,
                                      color: theme.colorScheme.primary),
                                ],
                              ],
                            ),
                            // 'Today' says which day it is not. A trading day that
                            // runs to 04:00 carries the previous date for four
                            // hours of every night, and the figures under a bare
                            // 'Today' then read as the wrong day's.
                            if (period.label(_today) != period.dateLabel)
                              Text(
                                period.dateLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: atPresent ? null : () => _step(1),
                  tooltip: 'Next',
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
            // Only shown in the small hours, and only on the day view, which
            // is the one place the cutoff can be mistaken for a lost day.
            if (atPresent &&
                period.granularity == StatsGranularity.day &&
                _beforeCutoff)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Past midnight, so this trading day is still open — it runs '
                  'to $cutoffHour:00, and anything rung up now counts here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReport(Session session, PeriodReport report) {
    final period = report.period;
    final total = report.total;
    final previous = report.previousTotal;
    final money = moneyFormat(session.store);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: PageBody(
          child: Column(
            spacing: 20,
            children: <Widget>[
              StatCardGrid(
                children: [
                  StatCard(
                    title: 'Revenue',
                    icon: Symbols.money_bag,
                    value: money.format(total.revenue),
                    trailing: ChangeBadge(
                      change:
                          PeriodReport.change(total.revenue, previous.revenue),
                    ),
                  ),
                  StatCard(
                    title: 'Orders',
                    icon: Icons.receipt_long_outlined,
                    value:
                        NumberFormat.decimalPattern().format(total.orderCount),
                    trailing: ChangeBadge(
                      change: PeriodReport.change(
                          total.orderCount, previous.orderCount),
                    ),
                  ),
                  StatCard(
                    title: 'Gross profit',
                    icon: Icons.trending_up_rounded,
                    value: money.format(total.grossProfit),
                    trailing: ChangeBadge(
                      change: PeriodReport.change(
                          total.grossProfit, previous.grossProfit),
                    ),
                  ),
                  StatCard(
                    title: 'Per head',
                    icon: Icons.groups_outlined,
                    value: money.format(total.averageGuestSpend.round()),
                    trailing: ChangeBadge(
                      change: PeriodReport.change(
                          total.averageGuestSpend, previous.averageGuestSpend),
                    ),
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
            ],
          ),
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
  Widget _buildTargetGauge(Store store, StatsPeriod period, DailyStats total) {
    final elapsed = period.elapsedDays(_today).clamp(1, period.dayCount);
    return _TargetProgress(
      current: total.orderCount,
      target: store.targets.dailyOrders * elapsed,
    );
  }

  /// How the takings moved inside the period: by hour for a single day, by
  /// trading day for a week or a month.
  Widget _buildTrendChart(Store store, PeriodReport report) {
    final period = report.period;

    if (period.granularity == StatsGranularity.day) {
      return _buildCartesianChart(
        store,
        'Revenue by hour',
        _hourlyData(store, report.total),
      );
    }

    // Days with no takings have no document at all, so they are filled back in
    // here — a chart that silently skips the days a shop was closed makes a
    // four-day week look like a full one.
    final byDate = {for (final day in report.days) day.businessDate: day};
    final data = <ChartPoint>[];
    for (var offset = 0; offset < period.dayCount; offset++) {
      final date = DateTime(
          period.start.year, period.start.month, period.start.day + offset);
      if (date.isAfter(_today)) break;
      data.add(ChartPoint(
        label: DateFormat.Md().format(date),
        value: byDate[formatBusinessDate(date)]?.revenue ?? 0,
      ));
    }
    return _buildCartesianChart(store, 'Revenue by day', data);
  }

  /// Hours from the first sale of the trading day to the last, gaps included,
  /// so a lunchtime peak and a quiet mid-afternoon keep their real shape.
  ///
  /// Walked in *trading-day* order rather than 0-23. With a 04:00 cutoff, an
  /// order rung up at 01:00 belongs to the day that started the previous
  /// morning — sorting by the clock printed it as the first column of that
  /// day, before the shop had opened, and a chart that puts the night's last
  /// sale before lunch is not a timeline.
  List<ChartPoint> _hourlyData(Store store, DailyStats total) {
    final sold = total.byHour.keys.map(int.tryParse).whereType<int>().toSet();
    if (sold.isEmpty) return const [];

    // 04, 05, … 23, 00, 01, 02, 03 for a store that rolls over at four. A
    // cutoff of zero gives plain 0-23, which is what a daytime shop wants.
    final tradingDay = [
      for (var i = 0; i < 24; i++) (store.dayCutoffHour + i) % 24,
    ];
    final first = tradingDay.indexWhere(sold.contains);
    final last = tradingDay.lastIndexWhere(sold.contains);

    return [
      for (var i = first; i <= last; i++)
        ChartPoint(
          label: '${tradingDay[i].toString().padLeft(2, '0')}:00',
          value: total.byHour['${tradingDay[i]}']?.revenue ?? 0,
        ),
    ];
  }

  /// Best sellers by units. Capped, because a month can span the whole menu and
  /// forty columns on a phone are unreadable.
  /// Best sellers, as horizontal bars.
  ///
  /// Was ten vertical columns with the dish names rotated 45° underneath.
  /// Dish names are long, categorical, and frequently Chinese — none of which
  /// survives being turned on its side and squeezed under a column. Laid
  /// horizontally the names sit flat and left-aligned, the bars read as a
  /// ranking, and the chart grows downward rather than being crushed sideways.
  Widget _buildTopDishesChart(DailyStats total) {
    return RankedBars(
      title: 'Top dishes',
      points: [
        for (final item in total.itemsByQty.take(10))
          ChartPoint(label: item.name, value: item.qty),
      ],
    );
  }

  /// One column chart, with the app's colours and the store's money on it.
  Widget _buildCartesianChart(
    Store store,
    String chartTitle,
    List<ChartPoint> data,
  ) =>
      ColumnChart(
        title: chartTitle,
        points: data,
        formatValue: moneyFormat(store).format,
      );
}

/// Orders rung up against the target for the days that have actually happened.
///
/// Replaces an `SfRadialGauge`: a half-circle dial that took a third of the
/// screen to say "118 / 200, 59%" — three facts a bar and a line of text carry
/// in a fraction of the space, leaving it for the trend chart underneath,
/// which has far more to say. The dial's sweep gradient and Times italic were
/// also lifted from a Syncfusion sample and matched nothing else in the app.
class _TargetProgress extends StatelessWidget {
  const _TargetProgress({required this.current, required this.target});

  final num current;
  final num target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final safeTarget = target <= 0 ? 1 : target;
    final fraction = (current / safeTarget).clamp(0.0, 1.0).toDouble();
    final percent = (current / safeTarget * 100).round();
    final met = current >= safeTarget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Orders against target', style: theme.textTheme.titleMedium),
            const Spacer(),
            Text('$current',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: met ? scheme.primary : scheme.onSurface,
                  fontWeight: FontWeight.bold,
                )),
            Text(' / $safeTarget',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 12,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor:
                AlwaysStoppedAnimation(met ? scheme.tertiary : scheme.primary),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          met ? '$percent% of target — met' : '$percent% of target so far',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Shown for a period with no trade in it.
class _EmptyPeriod extends StatelessWidget {
  const _EmptyPeriod({
    required this.label,
    required this.atPresent,
    required this.storeId,
  });

  final String label;

  /// Whether the period on screen contains today — the only case where
  /// "ring one up" is a sensible offer rather than a confusing one.
  final bool atPresent;

  final String storeId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Nothing was sold in $label',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              atPresent
                  ? 'Orders appear here the moment they are rung up.'
                  : 'Swipe, or use the arrows above, to look at another '
                      'period.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (atPresent) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => AddOrder(storeId)),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add an order'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

///Chart sample data
