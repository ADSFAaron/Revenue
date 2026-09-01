import '../models/daily_stats.dart';
import '../models/store.dart';

/// One weekday-and-hour square of the heatmap, averaged over every occurrence
/// of that weekday in the range.
class DemandCell {
  const DemandCell({
    required this.weekday,
    required this.hour,
    required this.averageOrders,
    required this.averageRevenue,
    required this.averageGuests,
  });

  /// 1 = Monday .. 7 = Sunday, matching [DateTime.weekday].
  final int weekday;

  /// 0-23.
  final int hour;

  final double averageOrders;
  final double averageRevenue;
  final double averageGuests;
}

/// A dish's expected demand on a given weekday.
class ItemForecast {
  const ItemForecast({
    required this.itemId,
    required this.name,
    required this.averageQty,
    required this.observations,
    required this.maxQty,
  });

  final String itemId;
  final String name;

  /// Units sold on a typical instance of the weekday.
  final double averageQty;

  /// How many of that weekday the average is drawn from. One Saturday is an
  /// anecdote, not a pattern, so this travels with the number.
  final int observations;

  /// The busiest single occurrence seen. Preparing to the average sells out
  /// half the time; this is the headroom.
  final int maxQty;

  bool get isReliable => observations >= 3;
}

/// When the shop is busy, broken down by weekday and hour, and what it sells on
/// each day of the week.
///
/// Two dimensions on purpose. A flat 24-hour chart averages Tuesday evening
/// together with Saturday evening, which in a restaurant are two different
/// businesses — the whole point of the report is telling them apart.
///
/// Built entirely from the daily rollups, so a quarter costs about ninety
/// document reads rather than a pass over every order.
class DemandProfile {
  const DemandProfile._({
    required this.cells,
    required this.observationsByWeekday,
    required this.itemsByWeekday,
    required this.dayCutoffHour,
  });

  /// Keyed by (weekday, hour). Squares with no trade are simply absent.
  final Map<(int, int), DemandCell> cells;

  /// How many trading days of each weekday the range actually contained.
  ///
  /// Averages are divided by this rather than by the number of weeks: a range
  /// covering four Tuesdays and five Wednesdays would otherwise make Wednesday
  /// look 25% busier than it is. Days the shop did not trade have no rollup
  /// document at all and so are not counted, which is what stops a regular
  /// closing day from dragging its own average toward zero.
  final Map<int, int> observationsByWeekday;

  final Map<int, List<ItemForecast>> itemsByWeekday;

  /// The hour the store's trading day rolls over, which is what puts the hours
  /// in order. See [activeHours].
  final int dayCutoffHour;

  bool get isEmpty => cells.isEmpty;

  static const List<String> weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static String weekdayName(int weekday) => weekdayNames[weekday - 1];

  DemandCell? cell(int weekday, int hour) => cells[(weekday, hour)];

  /// Hours that saw any trade, across the whole range — the span the heatmap
  /// needs to draw. A shop open noon to nine should not be given a grid of
  /// twenty-four columns, twelve of which are always empty.
  ///
  /// In *trading-day* order, not clock order: a shop whose day rolls over at
  /// 04:00 runs 04, 05, … 23, 00, 01, 02, 03. Sorting 0-23 put the 01:00 sales
  /// — which happen at the end of that trading day, after the late diners —
  /// at the front of the heatmap, before the shop had opened. It also made the
  /// overnight closure look like a quiet stretch *inside* the day, which is
  /// the one thing `_quietestStretch` in headline.dart exists not to report.
  List<int> get activeHours {
    final present = cells.keys.map((key) => key.$2).toSet();
    return [
      for (var i = 0; i < 24; i++)
        if (present.contains((dayCutoffHour + i) % 24))
          (dayCutoffHour + i) % 24,
    ];
  }

  List<int> get activeWeekdays {
    final days = observationsByWeekday.keys.toList()..sort();
    return days;
  }

  /// The busiest weekday-and-hour square by order count.
  DemandCell? get peak {
    DemandCell? best;
    for (final cell in cells.values) {
      if (best == null || cell.averageOrders > best.averageOrders) best = cell;
    }
    return best;
  }

  /// What to prep for a given weekday, busiest dish first.
  List<ItemForecast> forecastFor(int weekday) =>
      itemsByWeekday[weekday] ?? const [];

  /// Builds the profile from a range of daily rollups.
  ///
  /// [dayCutoffHour] is the store's, and only orders the hours — it never
  /// moves a figure between days, because the rollups are already keyed by the
  /// business date the cutoff produced.
  factory DemandProfile.from(
    Iterable<DailyStats> days, {
    int dayCutoffHour = 0,
  }) {
    // Sums first, divided through by the observation counts at the end.
    final orderSums = <(int, int), double>{};
    final revenueSums = <(int, int), double>{};
    final guestSums = <(int, int), double>{};
    final observations = <int, int>{};
    final itemSums = <int, Map<String, (String name, int qty, int max)>>{};

    for (final day in days) {
      if (day.isEmpty) continue;
      final date = DateTime.tryParse(day.businessDate);
      if (date == null) continue;
      final weekday = date.weekday;
      observations[weekday] = (observations[weekday] ?? 0) + 1;

      day.byHour.forEach((hourKey, bucket) {
        final hour = int.tryParse(hourKey);
        if (hour == null) return;
        final key = (weekday, hour);
        orderSums[key] = (orderSums[key] ?? 0) + bucket.orders;
        revenueSums[key] = (revenueSums[key] ?? 0) + bucket.revenue;
        guestSums[key] = (guestSums[key] ?? 0) + bucket.guests;
      });

      final items = itemSums.putIfAbsent(weekday, () => {});
      day.byItem.forEach((itemId, stat) {
        final existing = items[itemId];
        items[itemId] = (
          stat.name.isNotEmpty ? stat.name : (existing?.$1 ?? ''),
          (existing?.$2 ?? 0) + stat.qty,
          stat.qty > (existing?.$3 ?? 0) ? stat.qty : (existing?.$3 ?? 0),
        );
      });
    }

    final cells = <(int, int), DemandCell>{};
    orderSums.forEach((key, orders) {
      final count = observations[key.$1] ?? 1;
      cells[key] = DemandCell(
        weekday: key.$1,
        hour: key.$2,
        averageOrders: orders / count,
        averageRevenue: (revenueSums[key] ?? 0) / count,
        averageGuests: (guestSums[key] ?? 0) / count,
      );
    });

    final itemsByWeekday = <int, List<ItemForecast>>{};
    itemSums.forEach((weekday, items) {
      final count = observations[weekday] ?? 1;
      itemsByWeekday[weekday] = items.entries
          .map((entry) => ItemForecast(
                itemId: entry.key,
                name: entry.value.$1,
                averageQty: entry.value.$2 / count,
                observations: count,
                maxQty: entry.value.$3,
              ))
          .toList()
        ..sort((a, b) => b.averageQty.compareTo(a.averageQty));
    });

    return DemandProfile._(
      cells: cells,
      observationsByWeekday: observations,
      itemsByWeekday: itemsByWeekday,
      dayCutoffHour: dayCutoffHour,
    );
  }

  /// The weekday the store's next trading day falls on, so the prep list can
  /// open on the day it is actually needed for.
  static int nextTradingWeekday(Store store) {
    final today = parseBusinessDate(store.currentBusinessDate);
    return DateTime(today.year, today.month, today.day + 1).weekday;
  }
}
