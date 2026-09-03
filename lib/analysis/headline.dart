import 'demand_profile.dart';
import 'menu_engineering.dart';

/// Which of the Insights tabs a headline is about.
enum HeadlineTopic { menu, busyTimes, prep }

/// How loudly a headline should be presented.
enum HeadlineSeverity {
  /// Something is costing money now.
  warning,

  /// Worth acting on, but nothing is on fire.
  advice,

  /// Going well — say so, so the page is not only ever bad news.
  good,
}

/// One sentence a shop owner can act on.
class Headline {
  const Headline({
    required this.severity,
    required this.topic,
    required this.title,
    required this.detail,
  });

  final HeadlineSeverity severity;
  final HeadlineTopic topic;

  /// The finding, as a sentence with the number in it.
  final String title;

  /// What to do about it, or why it matters.
  final String detail;
}

/// Reads the finished reports and states what they add up to.
///
/// The reports themselves were already correct — a matrix, a heatmap, a prep
/// list — but each one is a table the reader has to interpret. Insights sat
/// behind an unlabelled icon partly because opening it gave you homework
/// rather than an answer. This turns the same numbers into sentences, so the
/// page leads with what changed and the tables become the evidence.
///
/// Nothing here fetches: it runs on reports already in hand.
List<Headline> headlinesFrom({
  required MenuEngineering matrix,
  required DemandProfile demand,
  required int windowDays,
}) {
  final headlines = <Headline>[];

  // ------------------------------------------------------------- food cost
  final foodCost = matrix.foodCostRate;
  if (foodCost != null) {
    final percent = (foodCost * 100).toStringAsFixed(1);
    final line = (MenuEngineering.foodCostWarningRate * 100).round();
    // Says how much of the business the figure speaks for, rather than the old
    // "covers only the dishes with costs on file" — which read the same at 95%
    // coverage as at 20%, and at 20% the number in front of it is a sample of
    // the menu rather than a fact about the shop.
    final covers = _coverageSentence(matrix);
    if (matrix.foodCostIsHigh) {
      headlines.add(Headline(
        severity: HeadlineSeverity.warning,
        topic: HeadlineTopic.menu,
        title: 'Food cost is $percent%, above the $line% watch line',
        detail: 'Usually pricing, portioning or waste. $covers',
      ));
    } else {
      headlines.add(Headline(
        severity: HeadlineSeverity.good,
        topic: HeadlineTopic.menu,
        title: 'Food cost is $percent%, within the usual range',
        detail: covers,
      ));
    }
  }

  // ------------------------------------------------------------------ dogs
  final dogs = matrix.ofClass(MenuClass.dog);
  if (dogs.isNotEmpty && matrix.items.isNotEmpty) {
    final menuShare = (dogs.length / matrix.items.length * 100).round();
    final dogRevenue = dogs.fold<int>(0, (sum, item) => sum + item.revenue);
    final revenueShare = matrix.totalRevenue == 0
        ? 0
        : (dogRevenue / matrix.totalRevenue * 100).round();
    headlines.add(Headline(
      severity: revenueShare * 2 < menuShare
          ? HeadlineSeverity.warning
          : HeadlineSeverity.advice,
      topic: HeadlineTopic.menu,
      title: '${dogs.length} ${_dish(dogs.length)} earn little and sell '
          'little — $menuShare% of the menu, $revenueShare% of takings',
      detail: 'Every one of them still costs prep, stock and a line on the '
          'menu. ${dogs.take(3).map((d) => d.name).join(', ')}'
          '${dogs.length > 3 ? '…' : ''}',
    ));
  }

  // ------------------------------------------------------------ plowhorses
  final plowhorses = matrix.ofClass(MenuClass.plowhorse);
  if (plowhorses.isNotEmpty) {
    final worst = plowhorses.first;
    headlines.add(Headline(
      severity: HeadlineSeverity.advice,
      topic: HeadlineTopic.menu,
      title: '${worst.name} sells well but earns thinly — ${worst.qty} sold, '
          '${worst.unitMargin.round()} margin each',
      detail: plowhorses.length == 1
          ? 'Repricing, resizing or sourcing it cheaper moves more money than '
              'the same change on any quiet dish.'
          : 'One of ${plowhorses.length} popular dishes below the menu\'s '
              'average margin.',
    ));
  }

  // --------------------------------------------------------------- puzzles
  final puzzles = matrix.ofClass(MenuClass.puzzle);
  if (puzzles.isNotEmpty) {
    headlines.add(Headline(
      severity: HeadlineSeverity.advice,
      topic: HeadlineTopic.menu,
      title: '${puzzles.length} profitable ${_dish(puzzles.length)} '
          '${puzzles.length == 1 ? 'is' : 'are'} being overlooked',
      detail: 'Good margin, few orders — usually a menu-position or '
          'upselling problem. ${puzzles.take(3).map((p) => p.name).join(', ')}'
          '${puzzles.length > 3 ? '…' : ''}',
    ));
  }

  // ------------------------------------------------------------ uncosted
  if (matrix.unclassified.isNotEmpty) {
    final count = matrix.unclassified.length;
    headlines.add(Headline(
      // With nothing costed at all, every report below is empty — that is the
      // most important thing on the page, not a footnote.
      severity: matrix.items.isEmpty
          ? HeadlineSeverity.warning
          : HeadlineSeverity.advice,
      topic: HeadlineTopic.menu,
      title: '$count ${_dish(count)} ${count == 1 ? 'has' : 'have'} no cost '
          'recorded',
      detail: matrix.items.isEmpty
          ? 'Nothing on the menu is costed, so none of these reports can tell '
              'you what actually makes money.'
          : 'They are left out of the matrix — with no cost on file a dish '
              'looks like pure profit. ${_coverageSentence(matrix)}',
    ));
  }

  // ------------------------------------------------------------ peak hour
  final peak = demand.peak;
  if (peak != null) {
    final day = DemandProfile.weekdayName(peak.weekday);
    headlines.add(Headline(
      severity: HeadlineSeverity.advice,
      topic: HeadlineTopic.busyTimes,
      title: 'Busiest hour is $day at ${_hour(peak.hour)} — '
          '${peak.averageOrders.toStringAsFixed(1)} orders',
      detail: 'Averaged over the ${_tradingDays(demand)} trading days in the '
          'last $windowDays. Staff and prep to this, not to the daily total.',
    ));
  }

  // ---------------------------------------------------------- quiet stretch
  final quiet = _quietestStretch(demand);
  if (quiet != null) {
    headlines.add(Headline(
      severity: HeadlineSeverity.advice,
      topic: HeadlineTopic.busyTimes,
      title: '${DemandProfile.weekdayName(quiet.$1)} '
          '${_hour(quiet.$2)}–${_hour(quiet.$3 + 1)} averages under one order',
      detail: 'The cheapest hours you own. Either a slot worth promoting into, '
          'or hours worth not being open for.',
    ));
  }

  // Warnings first, then advice, then the reassuring one — a page that opens
  // on "food cost is fine" has buried its own point.
  headlines.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return headlines;
}

String _dish(int count) => count == 1 ? 'dish' : 'dishes';

/// How much of the shop's takings the cost figures actually describe.
String _coverageSentence(MenuEngineering matrix) {
  final coverage = matrix.revenueCoverage;
  if (coverage == null) return '';
  final percent = (coverage * 100).round();
  if (percent >= 99) return 'Covers effectively all of your takings.';
  return matrix.coverageIsLow
      ? 'Covers $percent% of takings — cost the rest before trusting this.'
      : 'Covers $percent% of takings.';
}

String _hour(int hour) => '${(hour % 24).toString().padLeft(2, '0')}:00';

int _tradingDays(DemandProfile demand) =>
    demand.observationsByWeekday.values.fold(0, (a, b) => a + b);

/// The longest run of open-but-dead hours on a single weekday.
///
/// Only counts hours inside the shop's actual trading span — the gap between
/// lunch and dinner service is the finding; being shut overnight is not.
(int weekday, int from, int to)? _quietestStretch(DemandProfile demand) {
  final hours = demand.activeHours;
  if (hours.length < 3) return null;

  (int, int, int)? best;
  var bestLength = 1; // A single dead hour is noise, not a pattern.

  for (final weekday in demand.activeWeekdays) {
    int? runStart;
    for (final hour in hours) {
      final orders = demand.cell(weekday, hour)?.averageOrders ?? 0;
      if (orders < 1.0) {
        runStart ??= hour;
        final length = hour - runStart + 1;
        if (length > bestLength) {
          bestLength = length;
          best = (weekday, runStart, hour);
        }
      } else {
        runStart = null;
      }
    }
  }
  return best;
}
