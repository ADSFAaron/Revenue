import 'dart:math' as math;

import '../models/order.dart';

/// "People who order A also order B" — one rule, with the three numbers that
/// say whether it is worth acting on.
class BasketRule {
  const BasketRule({
    required this.antecedentId,
    required this.antecedentName,
    required this.consequentId,
    required this.consequentName,
    required this.together,
    required this.antecedentCount,
    required this.support,
    required this.confidence,
    required this.confidenceLowerBound,
    required this.lift,
  });

  final String antecedentId;
  final String antecedentName;
  final String consequentId;
  final String consequentName;

  /// Orders containing both dishes.
  final int together;

  /// Orders containing the first dish.
  final int antecedentCount;

  /// Share of all orders containing both, 0..1. Guards against acting on a
  /// pairing that is real but happens twice a month.
  final double support;

  /// Of the orders containing A, the share that also contained B, 0..1. This is
  /// the number to read out loud: "62% of beef noodle orders add a tea egg."
  final double confidence;

  /// The cautious end of [confidence]: the lower bound of its 95% Wilson score
  /// interval.
  ///
  /// [confidence] is a point estimate and says nothing about how much evidence
  /// is behind it — 4 out of 5 and 400 out of 500 are both 80%. This is what
  /// 4 out of 5 is worth once that is taken into account, and it is what the
  /// rule has to clear to be reported at all.
  final double confidenceLowerBound;

  /// Confidence divided by how often B is ordered anyway.
  ///
  /// Kept for display. It answers "how much more often than usual", which is
  /// the shape of the finding, but it is not what decides whether the finding
  /// is real — see [confidenceLowerBound] for that. A drink that appears in
  /// 80% of *all* orders will show 80% confidence behind every dish on the
  /// menu, and lift is what shows it has nothing to do with the dish.
  ///
  /// The denominator is [BasketAnalysis.basketCount] rather than
  /// [BasketAnalysis.multiItemBasketCount]. That is a choice: in a shop where
  /// most tickets carry a single dish it makes lift read lower than the pairing
  /// deserves, which errs toward under-claiming.
  final double lift;

  String get sentence =>
      '${(confidence * 100).round()}% of $antecedentName orders '
      'also include $consequentName';
}

/// Market basket analysis over a period's orders.
///
/// The data structure is a natural fit: one order document already *is* one
/// basket, with its dishes in an array, so no reshaping is needed.
///
/// Unlike the rest of the reports this one reads the orders themselves rather
/// than the daily rollups — a rollup has already thrown away which dishes
/// arrived on the same ticket, which is the entire question here. That makes it
/// the most expensive report in the app, so it is loaded on request rather than
/// alongside everything else.
class BasketAnalysis {
  const BasketAnalysis({
    required this.rules,
    required this.basketCount,
    required this.multiItemBasketCount,
  });

  final List<BasketRule> rules;

  /// Completed orders examined.
  final int basketCount;

  /// Orders with two or more distinct dishes — the only ones that can produce a
  /// pairing at all. A takeaway shop selling one item per ticket will find
  /// nothing here, and that is a fact about the shop, not a failure.
  final int multiItemBasketCount;

  bool get isEmpty => rules.isEmpty;

  /// Minimum orders a pair must appear in before it is reported.
  ///
  /// A floor under the statistics below rather than the test itself: a pair
  /// seen three times can clear a significance test on a tiny antecedent, and
  /// still is not something to change a menu over.
  static const int minimumTogether = 5;

  /// z for a 95% interval.
  static const double _z = 1.959964;

  /// The lower end of the Wilson score interval for [successes] of [trials].
  ///
  /// This replaced a flat `lift >= 1.05` cut, which was not a test at all at
  /// the sample sizes this report runs on. With five orders behind a pairing, a
  /// 5% excess over chance is inside the noise — yet the page printed a
  /// sentence from it in the same confident voice it uses for a pairing seen
  /// five hundred times. Wilson is the standard interval for a proportion at
  /// small n, where the textbook normal approximation misbehaves badly and can
  /// even produce bounds below zero.
  ///
  /// The comparison is against the unconditional rate of B, so a rule survives
  /// only when ordering A makes B more likely by more than the evidence's own
  /// uncertainty.
  static double wilsonLowerBound(int successes, int trials) {
    if (trials <= 0) return 0;
    final p = successes / trials;
    const z2 = _z * _z;
    final centre = p + z2 / (2 * trials);
    final margin = _z *
        math.sqrt(p * (1 - p) / trials + z2 / (4 * trials * trials));
    return ((centre - margin) / (1 + z2 / trials)).clamp(0.0, 1.0);
  }

  factory BasketAnalysis.from(
    Iterable<Order> orders, {
    int minimumTogether = minimumTogether,
  }) {
    final itemCounts = <String, int>{};
    final itemNames = <String, String>{};
    final pairCounts = <(String, String), int>{};
    var basketCount = 0;
    var multiItemBasketCount = 0;

    for (final order in orders) {
      // A voided sale never happened; counting it would let a mis-punched
      // ticket invent a pairing.
      if (order.status != OrderStatus.completed) continue;
      basketCount++;

      // Distinct dishes: ordering two of the same thing is not a pairing, and
      // the quantity is irrelevant to whether they travelled together.
      final ids = <String>{};
      for (final line in order.items) {
        if (line.itemId.isEmpty) continue;
        ids.add(line.itemId);
        itemNames.putIfAbsent(line.itemId, () => line.name);
      }
      if (ids.isEmpty) continue;

      for (final id in ids) {
        itemCounts[id] = (itemCounts[id] ?? 0) + 1;
      }
      if (ids.length < 2) continue;
      multiItemBasketCount++;

      // Sorted so that (A,B) and (B,A) land in the same bucket; both
      // directions are read back out as separate rules below.
      final sorted = ids.toList()..sort();
      for (var i = 0; i < sorted.length; i++) {
        for (var j = i + 1; j < sorted.length; j++) {
          final key = (sorted[i], sorted[j]);
          pairCounts[key] = (pairCounts[key] ?? 0) + 1;
        }
      }
    }

    if (basketCount == 0) {
      return const BasketAnalysis(
        rules: [],
        basketCount: 0,
        multiItemBasketCount: 0,
      );
    }

    final rules = <BasketRule>[];
    pairCounts.forEach((pair, together) {
      if (together < minimumTogether) return;

      // Both directions: "beef noodles → tea egg" and "tea egg → beef noodles"
      // are different claims and usually have very different confidence, since
      // one dish may be far more common than the other.
      for (final (a, b) in [(pair.$1, pair.$2), (pair.$2, pair.$1)]) {
        final countA = itemCounts[a] ?? 0;
        final countB = itemCounts[b] ?? 0;
        if (countA == 0 || countB == 0) continue;

        final confidence = together / countA;
        final baseline = countB / basketCount;
        final lowerBound = wilsonLowerBound(together, countA);
        // Not `confidence > baseline`: that is the claim, and this is whether
        // the evidence supports it.
        if (lowerBound <= baseline) continue;
        final lift = confidence / baseline;

        rules.add(BasketRule(
          antecedentId: a,
          antecedentName: itemNames[a] ?? a,
          consequentId: b,
          consequentName: itemNames[b] ?? b,
          together: together,
          antecedentCount: countA,
          support: together / basketCount,
          confidence: confidence,
          confidenceLowerBound: lowerBound,
          lift: lift,
        ));
      }
    });

    // Confidence first: it is the number that turns into a sentence a member of
    // staff can act on at the counter.
    rules.sort((x, y) => y.confidence.compareTo(x.confidence));

    return BasketAnalysis(
      rules: rules,
      basketCount: basketCount,
      multiItemBasketCount: multiItemBasketCount,
    );
  }
}
