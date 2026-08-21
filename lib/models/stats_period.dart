import 'package:intl/intl.dart';

import 'store.dart';

/// The three spans the statistics page reports over.
enum StatsGranularity {
  day('Day'),
  week('Week'),
  month('Month');

  const StatsGranularity(this.label);

  final String label;
}

/// A run of consecutive trading days, plus the arithmetic for stepping between
/// runs and for finding the one to compare against.
///
/// This is the piece the statistics page was missing: Day, Week and Month all
/// resolved to the same single trading day, and the paging arrows had nothing
/// to page. Keeping the range arithmetic here rather than in the widget means
/// the comparison logic is testable without a Firestore or a screen.
///
/// [start] and [end] are inclusive trading days, not wall-clock instants — a
/// trading day runs to the store's `dayCutoffHour`, which the business date
/// strings already account for.
class StatsPeriod {
  const StatsPeriod({
    required this.granularity,
    required this.start,
    required this.end,
  });

  final StatsGranularity granularity;
  final DateTime start;
  final DateTime end;

  /// The period of [granularity] that [date] falls inside.
  factory StatsPeriod.containing(DateTime date, StatsGranularity granularity) {
    final day = DateTime(date.year, date.month, date.day);
    return switch (granularity) {
      StatsGranularity.day =>
        StatsPeriod(granularity: granularity, start: day, end: day),
      // Weeks run Monday to Sunday. A restaurant's week is not the calendar's
      // seven-day window ending today; comparing "this week" to "last week"
      // only means something if both start on the same weekday.
      StatsGranularity.week => StatsPeriod(
          granularity: granularity,
          start: _addDays(day, -(day.weekday - DateTime.monday)),
          end: _addDays(day, DateTime.sunday - day.weekday),
        ),
      StatsGranularity.month => StatsPeriod(
          granularity: granularity,
          start: DateTime(day.year, day.month, 1),
          // Day zero of the next month is the last day of this one, which
          // avoids hard-coding month lengths and gets February right.
          end: DateTime(day.year, day.month + 1, 0),
        ),
    };
  }

  /// The period containing the store's current trading day.
  factory StatsPeriod.current(Store store, StatsGranularity granularity) =>
      StatsPeriod.containing(
          parseBusinessDate(store.currentBusinessDate), granularity);

  String get fromBusinessDate => formatBusinessDate(start);

  String get toBusinessDate => formatBusinessDate(end);

  /// Trading days in the period, inclusive of both ends.
  int get dayCount => end.difference(start).inDays + 1;

  StatsPeriod get previous => switch (granularity) {
        StatsGranularity.day =>
          StatsPeriod.containing(_addDays(start, -1), granularity),
        StatsGranularity.week =>
          StatsPeriod.containing(_addDays(start, -7), granularity),
        StatsGranularity.month => StatsPeriod.containing(
            DateTime(start.year, start.month - 1, 1), granularity),
      };

  StatsPeriod get next => switch (granularity) {
        StatsGranularity.day =>
          StatsPeriod.containing(_addDays(end, 1), granularity),
        StatsGranularity.week =>
          StatsPeriod.containing(_addDays(end, 1), granularity),
        StatsGranularity.month => StatsPeriod.containing(
            DateTime(start.year, start.month + 1, 1), granularity),
      };

  /// Re-anchors this period's start onto another granularity, for when the
  /// user switches tab. Paging back to June and then tapping Day should land
  /// in June, not jump back to today.
  StatsPeriod withGranularity(StatsGranularity granularity) =>
      granularity == this.granularity
          ? this
          : StatsPeriod.containing(start, granularity);

  bool contains(DateTime day) =>
      !day.isBefore(start) && !day.isAfter(end);

  /// Whether this period has run its full length as of [today].
  bool isComplete(DateTime today) => today.isAfter(end);

  /// Trading days of this period that have actually happened by [today].
  ///
  /// A month two days old has two days of takings in it, not thirty.
  int elapsedDays(DateTime today) {
    if (today.isAfter(end)) return dayCount;
    if (today.isBefore(start)) return 0;
    return today.difference(start).inDays + 1;
  }

  /// The stretch of the previous period to compare this one against.
  ///
  /// Truncated to the same number of elapsed days, because the honest
  /// comparison for two days into August is the first two days of July — not
  /// all thirty-one of them. Without this, every month, week and today's own
  /// figures would open showing a catastrophic decline that is only an artifact
  /// of the period not being over yet.
  StatsPeriod comparableTo(DateTime today) {
    final elapsed = elapsedDays(today);
    final prior = previous;
    if (elapsed >= prior.dayCount) return prior;
    return StatsPeriod(
      granularity: prior.granularity,
      start: prior.start,
      end: _addDays(prior.start, elapsed - 1),
    );
  }

  /// How the period reads in the header, e.g. 'Today', 'August 2026',
  /// '10 – 16 Aug 2026'.
  String label(DateTime today) {
    switch (granularity) {
      case StatsGranularity.day:
        if (_isSameDay(start, today)) return 'Today';
        if (_isSameDay(start, _addDays(today, -1))) return 'Yesterday';
        return DateFormat.yMMMMd().format(start);
      case StatsGranularity.week:
        if (contains(today)) return 'This week';
        final sameMonth = start.month == end.month && start.year == end.year;
        final from = sameMonth
            ? DateFormat.d().format(start)
            : DateFormat.MMMd().format(start);
        return '$from – ${DateFormat.yMMMd().format(end)}';
      case StatsGranularity.month:
        if (contains(today)) return 'This month';
        return DateFormat.yMMMM().format(start);
    }
  }

  /// Wording for the comparison line, matching what [comparableTo] measured.
  String comparisonLabel(DateTime today) {
    final partial = !isComplete(today);
    return switch (granularity) {
      StatsGranularity.day => 'vs previous day',
      StatsGranularity.week =>
        partial ? 'vs same days last week' : 'vs previous week',
      StatsGranularity.month =>
        partial ? 'vs same days last month' : 'vs previous month',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is StatsPeriod &&
      other.granularity == granularity &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(granularity, start, end);

  @override
  String toString() => '$fromBusinessDate..$toBusinessDate';

  /// Date-only arithmetic. Built by normalising the day field rather than by
  /// adding a `Duration`, which would drift by an hour across a daylight-saving
  /// boundary and land on the wrong trading day.
  static DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
