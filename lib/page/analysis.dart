import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../analysis/basket_analysis.dart';
import '../analysis/demand_profile.dart';
import '../analysis/menu_engineering.dart';
import '../database/repositories.dart';
import '../models/daily_stats.dart';
import '../models/store.dart';

/// How far back the reports look.
///
/// Deliberately not tied to the statistics page's Day / Week / Month period.
/// A menu engineering matrix built from one Tuesday says nothing — every one of
/// these reports is a statement about a pattern, and a pattern needs enough
/// trading days underneath it to exist.
enum AnalysisWindow {
  days30('Last 30 days', 30),
  days90('Last 90 days', 90),
  days180('Last 180 days', 180);

  const AnalysisWindow(this.label, this.days);

  final String label;
  final int days;
}

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({required this.session, super.key});

  final Session session;

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 4, vsync: this);

  AnalysisWindow _window = AnalysisWindow.days90;
  late Future<List<DailyStats>> _days = _loadDays();

  Store get _store => widget.session.store;

  /// Inclusive range of trading days the current window covers.
  (String from, String to) get _range {
    final today = parseBusinessDate(_store.currentBusinessDate);
    final from =
        DateTime(today.year, today.month, today.day - (_window.days - 1));
    return (formatBusinessDate(from), formatBusinessDate(today));
  }

  Future<List<DailyStats>> _loadDays() {
    final (from, to) = _range;
    return statsRepository.fetchRange(
      widget.session.storeId,
      fromBusinessDate: from,
      toBusinessDate: to,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          PopupMenuButton<AnalysisWindow>(
            initialValue: _window,
            onSelected: (window) => setState(() {
              _window = window;
              _days = _loadDays();
            }),
            itemBuilder: (context) => [
              for (final window in AnalysisWindow.values)
                PopupMenuItem(value: window, child: Text(window.label)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(_window.label),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Menu'),
            Tab(text: 'Busy times'),
            Tab(text: 'Prep'),
            Tab(text: 'Pairings'),
          ],
        ),
      ),
      body: FutureBuilder<List<DailyStats>>(
        future: _days,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final days = snapshot.data!;
          if (days.isEmpty) {
            return Center(
              child: Text('No trading days in the ${_window.label.toLowerCase()}.'),
            );
          }

          final total = DailyStats.sum(days);
          final matrix = MenuEngineering.from(total);
          final demand = DemandProfile.from(days);

          return TabBarView(
            controller: _tabController,
            children: [
              _MenuMatrixTab(matrix: matrix, store: _store),
              _BusyTimesTab(demand: demand, store: _store),
              _PrepTab(demand: demand, store: _store),
              _PairingsTab(session: widget.session, range: _range),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- menu matrix

class _MenuMatrixTab extends StatelessWidget {
  const _MenuMatrixTab({required this.matrix, required this.store});

  final MenuEngineering matrix;
  final Store store;

  @override
  Widget build(BuildContext context) {
    if (matrix.items.isEmpty) {
      return _EmptyNotice(
        icon: Icons.receipt_long_outlined,
        title: 'Nothing to place on the matrix yet',
        body: matrix.unclassified.isEmpty
            ? 'No dishes were sold in this window.'
            : 'The ${matrix.unclassified.length} dishes sold have no cost '
                'recorded. Fill in costs under Store Settings → Edit Menu and '
                'this report can tell you which of them actually make money.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _FoodCostBanner(matrix: matrix),
        const SizedBox(height: 16),
        for (final menuClass in MenuClass.values) ...[
          _classSection(context, menuClass),
          const SizedBox(height: 16),
        ],
        if (matrix.unclassified.isNotEmpty) _unclassifiedSection(context),
      ],
    );
  }

  Widget _classSection(BuildContext context, MenuClass menuClass) {
    final items = matrix.ofClass(menuClass);
    final money = _money(store);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(menuClass), color: _colorFor(menuClass)),
                const SizedBox(width: 8),
                Text(
                  '${menuClass.label}  (${items.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(menuClass.advice,
                style: Theme.of(context).textTheme.bodySmall),
            const Divider(),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('None'),
              )
            else
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(item.name),
                  subtitle: Text('${item.qty} sold · '
                      '${money.format(item.unitMargin.round())} margin each'),
                  trailing: Text(money.format(item.profit)),
                ),
          ],
        ),
      ),
    );
  }

  Widget _unclassifiedSection(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Not costed (${matrix.unclassified.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Left out of the matrix on purpose: with no cost on file a dish '
                'looks like pure profit, which would make it a Star for the '
                'wrong reason.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(),
              for (final item in matrix.unclassified)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(item.name),
                  subtitle: Text('${item.qty} sold'),
                ),
            ],
          ),
        ),
      );

  static IconData _iconFor(MenuClass menuClass) => switch (menuClass) {
        MenuClass.star => Icons.star_rounded,
        MenuClass.plowhorse => Icons.agriculture_rounded,
        MenuClass.puzzle => Icons.extension_rounded,
        MenuClass.dog => Icons.pets_rounded,
      };

  static Color _colorFor(MenuClass menuClass) => switch (menuClass) {
        MenuClass.star => Colors.amber,
        MenuClass.plowhorse => Colors.orange,
        MenuClass.puzzle => Colors.blue,
        MenuClass.dog => Colors.grey,
      };
}

class _FoodCostBanner extends StatelessWidget {
  const _FoodCostBanner({required this.matrix});

  final MenuEngineering matrix;

  @override
  Widget build(BuildContext context) {
    final rate = matrix.foodCostRate;
    if (rate == null) return const SizedBox.shrink();

    final high = matrix.foodCostIsHigh;
    return Card(
      elevation: 0,
      color: high
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(high ? Icons.warning_amber_rounded : Icons.check_circle_outline),
        title: Text('Food cost ${(rate * 100).toStringAsFixed(1)}%'),
        subtitle: Text(high
            ? 'Above the ${(MenuEngineering.foodCostWarningRate * 100).round()}% '
                'watch line — usually pricing, portioning or waste. Covers only '
                'the dishes that have costs on file.'
            : 'Within the usual range. Covers only the dishes that have costs '
                'on file.'),
      ),
    );
  }
}

// ----------------------------------------------------------------- busy times

class _BusyTimesTab extends StatelessWidget {
  const _BusyTimesTab({required this.demand, required this.store});

  final DemandProfile demand;
  final Store store;

  @override
  Widget build(BuildContext context) {
    if (demand.isEmpty) {
      return const _EmptyNotice(
        icon: Icons.schedule,
        title: 'No trading hours recorded',
        body: 'Orders need to be rung up before a pattern can appear.',
      );
    }

    final hours = demand.activeHours;
    final weekdays = demand.activeWeekdays;
    final peak = demand.peak!;
    final busiest = peak.averageOrders;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.local_fire_department_rounded),
            title: Text('Busiest: ${DemandProfile.weekdayName(peak.weekday)} '
                'at ${_hourLabel(peak.hour)}'),
            subtitle: Text(
                '${peak.averageOrders.toStringAsFixed(1)} orders on a typical '
                '${DemandProfile.weekdayName(peak.weekday)}'),
          ),
        ),
        const SizedBox(height: 16),
        Text('Average orders per hour',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Weekday against hour, not a flat 24-hour chart: a Tuesday evening '
          'and a Saturday evening are two different shops.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        // Horizontal scroll so a long trading day keeps readable cells rather
        // than being squeezed into the screen width.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(width: 44),
                  for (final hour in hours)
                    SizedBox(
                      width: 34,
                      child: Text(
                        hour.toString().padLeft(2, '0'),
                        style: Theme.of(context).textTheme.labelSmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
              for (final weekday in weekdays)
                Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(DemandProfile.weekdayName(weekday),
                          style: Theme.of(context).textTheme.labelSmall),
                    ),
                    for (final hour in hours)
                      _HeatCell(
                        cell: demand.cell(weekday, hour),
                        busiest: busiest,
                        hour: hour,
                        weekday: weekday,
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Averaged over the ${demand.observationsByWeekday.values.fold(0, (a, b) => a + b)} '
          'trading days in this window. Days the shop did not open are not '
          'counted, so a regular closing day does not drag its own average down.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.cell,
    required this.busiest,
    required this.weekday,
    required this.hour,
  });

  final DemandCell? cell;
  final double busiest;
  final int weekday;
  final int hour;

  @override
  Widget build(BuildContext context) {
    final orders = cell?.averageOrders ?? 0;
    final intensity = busiest == 0 ? 0.0 : (orders / busiest).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: '${DemandProfile.weekdayName(weekday)} ${_hourLabel(hour)}\n'
          '${orders.toStringAsFixed(1)} orders on average',
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          // Lerping from the surface colour means an empty hour reads as
          // background rather than as a deliberate "zero" block.
          color: Color.lerp(scheme.surfaceContainerHighest, scheme.primary,
              intensity),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            orders < 0.05 ? '' : orders.toStringAsFixed(0),
            style: TextStyle(
              fontSize: 11,
              color: intensity > 0.55 ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------- prep

class _PrepTab extends StatefulWidget {
  const _PrepTab({required this.demand, required this.store});

  final DemandProfile demand;
  final Store store;

  @override
  State<_PrepTab> createState() => _PrepTabState();
}

class _PrepTabState extends State<_PrepTab> {
  late int _weekday = DemandProfile.nextTradingWeekday(widget.store);

  @override
  Widget build(BuildContext context) {
    final forecast = widget.demand.forecastFor(_weekday);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<int>(
            segments: [
              for (var weekday = 1; weekday <= 7; weekday++)
                ButtonSegment(
                  value: weekday,
                  label: Text(DemandProfile.weekdayName(weekday).substring(0, 1)),
                ),
            ],
            selected: {_weekday},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _weekday = selection.first),
          ),
        ),
        Expanded(
          child: forecast.isEmpty
              ? _EmptyNotice(
                  icon: Icons.no_food_outlined,
                  title: 'No ${DemandProfile.weekdayName(_weekday)} on record',
                  body: 'Either the shop does not open that day, or the window '
                      'is too short to contain one.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Text(
                      'What a typical ${DemandProfile.weekdayName(_weekday)} '
                      'sells, from ${forecast.first.observations} of them.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (!forecast.first.isReliable)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Card(
                          elevation: 0,
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const ListTile(
                            dense: true,
                            leading: Icon(Icons.info_outline),
                            title: Text('Fewer than three of this weekday'),
                            subtitle: Text(
                                'Treat these as a first guess rather than a '
                                'pattern — widen the window for a firmer one.'),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    for (final item in forecast)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.name),
                        subtitle: Text('busiest such day sold ${item.maxQty}'),
                        trailing: Text(
                          item.averageQty.toStringAsFixed(1),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- pairings

class _PairingsTab extends StatefulWidget {
  const _PairingsTab({required this.session, required this.range});

  final Session session;
  final (String, String) range;

  @override
  State<_PairingsTab> createState() => _PairingsTabState();
}

class _PairingsTabState extends State<_PairingsTab> {
  Future<BasketAnalysis>? _analysis;

  /// Loaded on a tap rather than with the page.
  ///
  /// This is the only report that reads the orders themselves — the daily
  /// rollups have already thrown away which dishes shared a ticket — so a
  /// six-month window here is thousands of document reads. Opening the tab
  /// should not spend them by accident.
  void _run() {
    setState(() {
      _analysis = orderRepository
          .fetchRange(
            widget.session.storeId,
            fromBusinessDate: widget.range.$1,
            toBusinessDate: widget.range.$2,
          )
          .then((orders) => BasketAnalysis.from(orders));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_analysis == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hub_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Which dishes get ordered together',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'This one reads every order in the window rather than the daily '
                'summaries, so it is the most expensive report in the app. Run '
                'it when you want it.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _run,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Analyse orders'),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<BasketAnalysis>(
      future: _analysis,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final analysis = snapshot.data!;
        if (analysis.isEmpty) {
          return _EmptyNotice(
            icon: Icons.hub_outlined,
            title: 'No pairings stand out',
            body: analysis.multiItemBasketCount == 0
                ? 'Every order in this window had a single dish on it, so there '
                    'is nothing to pair.'
                : 'Of ${analysis.basketCount} orders, '
                    '${analysis.multiItemBasketCount} had more than one dish, '
                    'but no combination came up often enough — or any more often '
                    'than chance — to be worth acting on.',
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'From ${analysis.basketCount} orders, '
              '${analysis.multiItemBasketCount} of them with more than one dish.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final rule in analysis.rules.take(20))
              Card(
                elevation: 0,
                child: ListTile(
                  title: Text(rule.sentence),
                  subtitle: Text('${rule.together} orders · '
                      '${rule.lift.toStringAsFixed(1)}× more often than '
                      '${rule.consequentName} is ordered in general'),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------- bits

class _EmptyNotice extends StatelessWidget {
  const _EmptyNotice({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(body,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

String _hourLabel(int hour) => '${hour.toString().padLeft(2, '0')}:00';

NumberFormat _money(Store store) => NumberFormat.currency(
      name: store.currency,
      symbol: store.currency == 'TWD' ? 'NT\$' : null,
      decimalDigits: 0,
    );
