import 'package:flutter/material.dart';

import '../analysis/basket_analysis.dart';
import '../analysis/demand_profile.dart';
import '../analysis/headline.dart';
import '../analysis/menu_engineering.dart';
import '../database/repositories.dart';
import '../models/daily_stats.dart';
import '../models/store.dart';
import '../settings/store_settings_edit_menu.dart';
import '../settings/user_manual.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';
import '../widgets/empty_state.dart';
import '../widgets/text_scale.dart';

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

/// The reports that say what to change, rather than what was sold.
///
/// Reached from the shell's second tab. It used to be pushed from an
/// unlabelled icon in the statistics app bar and took a [Session] from that
/// page; as a destination of its own it resolves one like every other tab.
class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage>
    with SingleTickerProviderStateMixin {
  /// Summary, then the four reports it draws on.
  late final TabController _tabController =
      TabController(length: 5, vsync: this);

  Session? _session;
  Object? _sessionError;

  AnalysisWindow _window = AnalysisWindow.days90;
  Future<List<DailyStats>>? _days;

  Store get _store => _session!.store;

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
      _session!.storeId,
      fromBusinessDate: from,
      toBusinessDate: to,
    );
  }

  @override
  void initState() {
    super.initState();
    loadSession().then((session) {
      if (!mounted) return;
      setState(() {
        _session = session;
        _days = _loadDays();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          // The one screen whose numbers need a glossary. A person looking
          // at "Plowhorse" has no way to know it is a verdict about this menu
          // rather than an absolute one, and nothing on the card can say so
          // without becoming an essay.
          IconButton(
            tooltip: 'What these mean',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const UserManual(initialTopic: ManualTopic.insights),
              ),
            ),
          ),
          // A custom `child` on a PopupMenuButton gets no ripple and no
          // tooltip, so this read as a caption rather than a control. The
          // check mark on the current window also says which one is active
          // without having to compare it against the label.
          PopupMenuButton<AnalysisWindow>(
            initialValue: _window,
            tooltip: 'How far back to look',
            onSelected: (window) => setState(() {
              _window = window;
              _days = _loadDays();
            }),
            itemBuilder: (context) => [
              for (final window in AnalysisWindow.values)
                PopupMenuItem(
                  value: window,
                  child: Row(
                    children: [
                      Icon(
                        window == _window
                            ? Icons.check
                            : Icons.check_box_outline_blank,
                        size: 18,
                        color: window == _window
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                      const SizedBox(width: 12),
                      Text(window.label),
                    ],
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.date_range_outlined, size: 20),
                  const SizedBox(width: 6),
                  Text(_window.label,
                      style: Theme.of(context).textTheme.labelLarge),
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
            Tab(text: 'Summary'),
            Tab(text: 'Menu'),
            Tab(text: 'Busy times'),
            Tab(text: 'Prep'),
            Tab(text: 'Pairings'),
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
    if (_session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<List<DailyStats>>(
      future: _days,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(
            snapshot.error!,
            onRetry: () => setState(() => _days = _loadDays()),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final days = snapshot.data!;
        if (days.isEmpty) {
          return EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'Nothing traded in the ${_window.label.toLowerCase()}',
            body: 'These reports describe patterns, and a pattern needs '
                'trading days underneath it. Ring up some orders, or widen '
                'the window from the menu above.',
          );
        }

        final total = DailyStats.sum(days);
        final matrix = MenuEngineering.from(total);
        final demand =
            DemandProfile.from(days, dayCutoffHour: _store.dayCutoffHour);

        return TabBarView(
          controller: _tabController,
          children: [
            _SummaryTab(
              headlines: headlinesFrom(
                matrix: matrix,
                demand: demand,
                windowDays: _window.days,
              ),
              storeId: _session!.storeId,
              onOpen: _openTopic,
            ),
            _MenuMatrixTab(matrix: matrix, store: _store),
            _BusyTimesTab(demand: demand, store: _store),
            _PrepTab(demand: demand, store: _store),
            _PairingsTab(session: _session!, range: _range),
          ],
        );
      },
    );
  }

  /// Jumps from a summary card to the report it was drawn from.
  void _openTopic(HeadlineTopic topic) {
    _tabController.animateTo(switch (topic) {
      HeadlineTopic.menu => 1,
      HeadlineTopic.busyTimes => 2,
      HeadlineTopic.prep => 3,
    });
  }
}

// -------------------------------------------------------------------- summary

/// What the reports below add up to, in sentences.
///
/// The first thing the tab opens on, and the reason Insights is worth a
/// destination of its own. Every other tab here is a table that the reader has
/// to interpret; this one states the finding and leaves the table as evidence,
/// one tap away.
class _SummaryTab extends StatelessWidget {
  const _SummaryTab({
    required this.headlines,
    required this.storeId,
    required this.onOpen,
  });

  final List<Headline> headlines;
  final String storeId;
  final void Function(HeadlineTopic topic) onOpen;

  @override
  Widget build(BuildContext context) {
    if (headlines.isEmpty) {
      return const EmptyState(
        icon: Icons.lightbulb_outline_rounded,
        title: 'Nothing stands out yet',
        body: 'Nothing in this window is far enough from the ordinary to be '
            'worth telling you about. Widen the window, or come back after a '
            'few more trading days.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      // One extra row: a pointer to Pairings, which is the fifth of five
      // scrollable tabs and so sits off the edge of a phone screen.
      itemCount: headlines.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => index < headlines.length
          ? _HeadlineCard(headline: headlines[index], onOpen: onOpen)
          : const _PairingsSignpost(),
    );
  }
}

/// One card on Insights: a glyph, a headline, a sentence under it.
///
/// Every card on this page used to build its own. Two hand-rolled a `Row`, one
/// used a `ListTile`, and a `ListTile` does not measure the way a `Row` does —
/// its leading slot has its own insets and its own gap to the title, so the
/// odd card out sat several points off the others down the left edge, which is
/// exactly the sort of thing that reads as "unfinished" without anybody being
/// able to say why.
///
/// The icon is centred in a box the height of one line of [titleMedium] rather
/// than aligned to the top of it. Top-aligning a 24pt glyph against a 24pt line
/// box is only correct if the glyph fills its box, and none of these do — the
/// warning triangle in particular has a point at the top and reads high.
class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.title,
    required this.detail,
    this.background,
    this.foreground,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color? background;
  final Color? foreground;
  final VoidCallback? onTap;

  /// One line of `titleMedium`: 16pt at the 1.5 line height Material gives it.
  static const double _titleLine = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = foreground ?? scheme.onSurface;

    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _titleLine,
            child: Center(child: Icon(icon, color: ink, size: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(color: ink),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: ink.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: _titleLine,
              child: Center(
                child: Icon(Icons.chevron_right_rounded, color: ink),
              ),
            ),
          ],
        ],
      ),
    );

    return Card(
      color: background,
      elevation: background == null ? null : 0,
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: body,
            ),
    );
  }
}

/// Points at the Pairings report, which has to be run by hand.
class _PairingsSignpost extends StatelessWidget {
  const _PairingsSignpost();

  @override
  Widget build(BuildContext context) => const _InsightCard(
        icon: Icons.hub_outlined,
        title: 'Which dishes get ordered together',
        detail: 'Reads every order rather than the daily summaries, so it runs '
            'only when you ask. Open the Pairings tab.',
      );
}

class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.headline, required this.onOpen});

  final Headline headline;
  final void Function(HeadlineTopic topic) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (background, foreground, icon) = switch (headline.severity) {
      HeadlineSeverity.warning => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.warning_amber_rounded,
        ),
      HeadlineSeverity.advice => (
          scheme.surfaceContainer,
          scheme.onSurface,
          Icons.tips_and_updates_outlined,
        ),
      HeadlineSeverity.good => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Icons.check_circle_outline,
        ),
    };

    return _InsightCard(
      icon: icon,
      title: headline.title,
      detail: headline.detail,
      background: background,
      foreground: foreground,
      onTap: () => onOpen(headline.topic),
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
      final uncosted = matrix.unclassified.length;
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Nothing to place on the matrix yet',
        body: uncosted == 0
            ? 'No dishes were sold in this window.'
            : 'The $uncosted dishes sold have no cost recorded, so this report '
                'cannot tell you which of them actually make money.',
        action: uncosted == 0
            ? null
            : FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StoreEditMenu(store.id),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Fill in costs'),
              ),
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
    final money = moneyFormat(store);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(menuClass),
                    color: _colorFor(menuClass, Theme.of(context).colorScheme)),
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

  /// Amber and orange were near-indistinguishable at icon size, and Star
  /// against Plowhorse is the one pair a reader most needs to tell apart.
  static Color _colorFor(MenuClass menuClass, ColorScheme scheme) =>
      switch (menuClass) {
        MenuClass.star => scheme.tertiary,
        MenuClass.plowhorse => scheme.primary,
        MenuClass.puzzle => scheme.secondary,
        MenuClass.dog => scheme.outline,
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
    final scheme = Theme.of(context).colorScheme;
    return _InsightCard(
      icon: high ? Icons.warning_amber_rounded : Icons.check_circle_outline,
      background: high ? scheme.errorContainer : scheme.surfaceContainerHighest,
      foreground: high ? scheme.onErrorContainer : scheme.onSurface,
      title: 'Food cost ${(rate * 100).toStringAsFixed(1)}%',
      detail: high
          ? 'Above the ${(MenuEngineering.foodCostWarningRate * 100).round()}% '
              'watch line — usually pricing, portioning or waste. Covers only '
              'the dishes that have costs on file.'
          : 'Within the usual range. Covers only the dishes that have costs '
              'on file.',
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
      return const EmptyState(
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
                  SizedBox(width: _heat(context, 44)),
                  for (final hour in hours)
                    SizedBox(
                      width: _heat(context, 34),
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
                      width: _heat(context, 44),
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

/// The heatmap's cell size, and the header widths that have to line up with
/// it, scaled by the phone's text size.
///
/// Fixed 32pt cells clipped their own numbers as soon as somebody turned the
/// system font up — which in a kitchen is the normal setting, not the odd one.
/// Capped, because a grid twenty-four hours wide runs off the side of a phone
/// before its numerals become the problem.
double _heat(BuildContext context, double size) =>
    scaledForText(context, size, cap: 1.6);

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Tooltip(
      message: '${DemandProfile.weekdayName(weekday)} ${_hourLabel(hour)}\n'
          '${orders.toStringAsFixed(1)} orders on average',
      child: Container(
        width: _heat(context, 32),
        height: _heat(context, 32),
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          // Lerping from the surface colour means an empty hour reads as
          // background rather than as a deliberate "zero" block.
          color: Color.lerp(
              scheme.surfaceContainerHighest, scheme.primary, intensity),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            orders < 0.05 ? '' : orders.toStringAsFixed(0),
            // The same label size as the axis it sits under, taken from the
            // text theme rather than written as an 11 here, so the system
            // font setting moves the cells and their headers together.
            style: theme.textTheme.labelSmall?.copyWith(
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
                  label:
                      Text(DemandProfile.weekdayName(weekday).substring(0, 1)),
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
              ? EmptyState(
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
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
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
              Icon(Icons.hub_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
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
          return ErrorView(snapshot.error!, onRetry: _run);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final analysis = snapshot.data!;
        if (analysis.isEmpty) {
          return EmptyState(
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

String _hourLabel(int hour) => '${hour.toString().padLeft(2, '0')}:00';
