import '../models/daily_stats.dart';

/// Where a dish lands on the popularity × profitability matrix.
enum MenuClass {
  /// Sells well and earns well. Protect it: do not reprice, resize or move it
  /// down the menu.
  star('Star', 'Sells well and earns well — leave it alone'),

  /// Sells well and earns little. The dangerous one: it tops every best-seller
  /// chart while diluting the margin on every plate that leaves the kitchen.
  plowhorse('Plowhorse', 'Popular but thin — reprice, resize or cut its cost'),

  /// Earns well but nobody orders it. Usually a menu-layout or upselling
  /// problem rather than a food problem.
  puzzle('Puzzle', 'Profitable but overlooked — promote it or move it up'),

  /// Neither sells nor earns. A candidate for removal.
  dog('Dog', 'Neither sells nor earns — consider dropping it');

  const MenuClass(this.label, this.advice);

  final String label;
  final String advice;
}

/// One dish placed on the matrix.
class MenuItemAnalysis {
  const MenuItemAnalysis({
    required this.stat,
    required this.menuClass,
    required this.unitMargin,
    required this.qtyShare,
  });

  final ItemStat stat;
  final MenuClass menuClass;

  /// Contribution margin per unit sold, in whole currency units.
  final double unitMargin;

  /// This dish's share of all units sold, 0..1.
  final double qtyShare;

  String get name => stat.name;
  int get qty => stat.qty;
  int get revenue => stat.revenue;
  int get profit => stat.profit;
}

/// The menu engineering matrix: dishes sorted into Stars, Plowhorses, Puzzles
/// and Dogs by popularity against profitability.
///
/// The framework restaurants have used since the 1980s (Kasavana & Smith), and
/// the reason a plain best-seller chart is not enough. A Plowhorse sits at the
/// top of that chart looking like the shop's champion while every plate of it
/// dilutes the margin — a ranking by units sold can never surface that.
///
/// Two thresholds, both relative to this menu rather than to any absolute
/// figure:
///
///  * **Popular** — the dish's share of units sold clears 70% of an even split
///    across the menu. The 70% is the industry-standard allowance for the fact
///    that a menu's sales are never evenly spread.
///  * **Profitable** — the dish's contribution margin per unit clears the
///    weighted average across everything sold.
class MenuEngineering {
  const MenuEngineering({
    required this.items,
    required this.unclassified,
    required this.insufficient,
    required this.averageUnitMargin,
    required this.popularityThreshold,
    required this.totalRevenue,
    required this.totalCost,
    required this.uncostedRevenue,
  });

  final List<MenuItemAnalysis> items;

  /// Dishes left out because they have no cost recorded.
  ///
  /// These are excluded rather than assumed to cost nothing. A dish with a
  /// blank cost would otherwise show a 100% margin and be crowned a Star,
  /// which is the single most misleading thing this report could do — and it
  /// would happen to precisely the dishes nobody has got round to costing.
  final List<ItemStat> unclassified;

  /// Dishes left unplaced because too few of them sold to place honestly.
  ///
  /// Separate from [unclassified] rather than folded into it. Both are "not on
  /// the matrix", but they are different problems with different fixes: one is
  /// answered by filling in a cost, the other only by more trading. A single
  /// bucket would have to tell somebody to go and cost a dish that is already
  /// costed.
  ///
  /// The instability this guards against is per-dish, not per-window, which is
  /// why the whole report is not gated on a day count. A shop can have three
  /// months of solid data and still have a dish that sold four plates in it,
  /// and it is only that dish's verdict that is worthless.
  final List<ItemStat> insufficient;

  final double averageUnitMargin;

  /// Share of units sold a dish must clear to count as popular.
  final double popularityThreshold;

  final int totalRevenue;
  final int totalCost;

  /// Takings from the dishes in [unclassified] — the ones with no cost on file.
  final int uncostedRevenue;

  /// The share of takings this report can actually speak for, 0..1.
  ///
  /// Every figure derived from costs is computed over the costed half of the
  /// menu only, which used to be expressed as the phrase "covers only the
  /// dishes with costs on file" repeated under each of them. That is a hedge,
  /// not a measurement: it reads identically at 95% coverage and at 20%, and at
  /// 20% the food-cost rate beside it is close to meaningless. Null when
  /// nothing sold at all.
  double? get revenueCoverage {
    final all = totalRevenue + uncostedRevenue;
    return all == 0 ? null : totalRevenue / all;
  }

  /// Below this, the cost figures describe a minority of the business and
  /// should be read as a sample rather than as the shop's numbers.
  static const double coverageWarningRate = 0.70;

  bool get coverageIsLow {
    final coverage = revenueCoverage;
    return coverage != null && coverage < coverageWarningRate;
  }

  /// How many of a dish must sell before the matrix will place it.
  ///
  /// Both axes are ratios, and under about ten units the numerator is small
  /// enough that one table changes the answer: a party ordering three of
  /// something can carry a dish across the popularity line on its own, and the
  /// margin beside it is an average over fewer than ten plates. A verdict that
  /// turns on one table is not a verdict, and "Dog — consider dropping it" is
  /// exactly the kind of confident sentence a shop should not be given on four
  /// observations.
  ///
  /// Flat rather than scaled to the window, deliberately. Widening from 30 days
  /// to 180 does not make four sales into a pattern; it only means the four
  /// took longer.
  static const int minimumUnits = 10;

  bool get isEmpty =>
      items.isEmpty && unclassified.isEmpty && insufficient.isEmpty;

  List<MenuItemAnalysis> ofClass(MenuClass menuClass) =>
      items.where((item) => item.menuClass == menuClass).toList();

  /// Food cost as a share of revenue, or null when nothing costed was sold.
  ///
  /// Covers only the dishes that have a cost on file — a rate computed over a
  /// half-costed menu would read far too low.
  double? get foodCostRate =>
      totalRevenue == 0 ? null : totalCost / totalRevenue;

  /// The usual industry warning line. An American benchmark; Taiwanese cost
  /// structures differ somewhat, so treat it as a flag to go and look rather
  /// than as a verdict.
  static const double foodCostWarningRate = 0.35;

  bool get foodCostIsHigh {
    final rate = foodCostRate;
    return rate != null && rate > foodCostWarningRate;
  }

  /// Builds the matrix from a period's rollup.
  factory MenuEngineering.from(DailyStats stats) {
    final costed = <ItemStat>[];
    final unclassified = <ItemStat>[];

    for (final item in stats.byItem.values) {
      if (item.qty <= 0) continue;
      // marginRate is null exactly when the dish has no usable cost — the same
      // rule the item stats already use, applied here so the two reports cannot
      // disagree about which dishes are costed.
      (item.marginRate == null ? unclassified : costed).add(item);
    }

    final uncostedRevenue =
        unclassified.fold<int>(0, (sum, item) => sum + item.revenue);

    if (costed.isEmpty) {
      return MenuEngineering(
        items: const [],
        unclassified: unclassified,
        insufficient: const [],
        averageUnitMargin: 0,
        popularityThreshold: 0,
        totalRevenue: 0,
        totalCost: 0,
        uncostedRevenue: uncostedRevenue,
      );
    }

    var totalQty = 0, totalRevenue = 0, totalCost = 0;
    for (final item in costed) {
      totalQty += item.qty;
      totalRevenue += item.revenue;
      totalCost += item.cost;
    }

    final averageUnitMargin = (totalRevenue - totalCost) / totalQty;
    // An even split would give every dish 1/n of the units; 70% of that is the
    // conventional bar for "pulls its weight".
    final popularityThreshold = 0.7 / costed.length;

    // Withheld from the matrix, but *not* from the arithmetic above. A thin
    // dish is still a real sale, so leaving it out of the totals would inflate
    // every other dish's share of units and shift the average margin it is
    // measured against. Only the verdict is withheld; no figure on this report
    // moves because of this line.
    final placed = <ItemStat>[];
    final insufficient = <ItemStat>[];
    for (final item in costed) {
      (item.qty >= minimumUnits ? placed : insufficient).add(item);
    }

    final items = placed.map((item) {
      final unitMargin = (item.revenue - item.cost) / item.qty;
      final qtyShare = item.qty / totalQty;
      final popular = qtyShare >= popularityThreshold;
      final profitable = unitMargin >= averageUnitMargin;

      return MenuItemAnalysis(
        stat: item,
        menuClass: popular
            ? (profitable ? MenuClass.star : MenuClass.plowhorse)
            : (profitable ? MenuClass.puzzle : MenuClass.dog),
        unitMargin: unitMargin,
        qtyShare: qtyShare,
      );
    }).toList()
      // Biggest sellers first inside each class, which is the order someone
      // scanning for something to act on reads in.
      ..sort((a, b) => b.qty.compareTo(a.qty));

    return MenuEngineering(
      items: items,
      unclassified: unclassified,
      insufficient: insufficient..sort((a, b) => b.qty.compareTo(a.qty)),
      averageUnitMargin: averageUnitMargin,
      popularityThreshold: popularityThreshold,
      totalRevenue: totalRevenue,
      totalCost: totalCost,
      uncostedRevenue: uncostedRevenue,
    );
  }
}
