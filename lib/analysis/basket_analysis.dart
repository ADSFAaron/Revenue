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

  /// Confidence divided by how often B is ordered anyway.
  ///
  /// The one that separates a finding from a coincidence. A drink that appears
  /// in 80% of *all* orders will show 80% confidence behind every dish on the
  /// menu; only lift shows that it has nothing to do with the dish. Above 1
  /// means the pair really does travel together.
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
  static const int minimumTogether = 5;

  /// Only pairings that occur more than chance would predict.
  static const double minimumLift = 1.05;

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
        final lift = confidence / (countB / basketCount);
        if (lift < minimumLift) continue;

        rules.add(BasketRule(
          antecedentId: a,
          antecedentName: itemNames[a] ?? a,
          consequentId: b,
          consequentName: itemNames[b] ?? b,
          together: together,
          antecedentCount: countA,
          support: together / basketCount,
          confidence: confidence,
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
