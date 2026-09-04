import '../models/daily_stats.dart';
import 'menu_engineering.dart';

/// One figure now, the same figure over the stretch before it.
///
/// A level on its own tells a shop owner nothing. NT$18,000 is a good Tuesday
/// or a bad one entirely depending on what the Tuesdays before it did, and
/// every headline on Insights used to state levels: "food cost is 34%",
/// "3 dishes earn little". True, and unactionable — 34% is an emergency in a
/// shop that ran at 28% last month and a success in one that ran at 41%.
class Comparison {
  const Comparison({
    required this.label,
    required this.current,
    required this.previous,
    this.asRate = false,
  });

  final String label;
  final double current;
  final double previous;

  /// Whether these are rates rather than amounts.
  ///
  /// Rates are compared in **percentage points**, not as a percentage of a
  /// percentage. "Food cost rose 10%" from 30% is unreadable — is that 33% or
  /// 40%? — where "rose 3 points, 30% to 33%" cannot be misread.
  final bool asRate;

  /// Fractional change, e.g. 0.12 for +12%.
  ///
  /// Null when the previous stretch was zero. There is no percentage change
  /// from nothing, and "+100%" for a shop's first week of trading, or the week
  /// after a holiday, is a number invented by the arithmetic rather than
  /// observed.
  double? get change {
    if (previous == 0) return null;
    return (current - previous) / previous;
  }

  /// Difference in percentage points, for [asRate] figures.
  double get pointChange => (current - previous) * 100;

  /// Whether the two are near enough to be the same.
  ///
  /// Under a point of movement is noise dressed as a finding, and a page that
  /// reports every one of those trains people to ignore all of them.
  bool get isFlat =>
      asRate ? pointChange.abs() < 1 : ((change ?? 0).abs() < 0.02);
}

/// A dish that changed quadrant between the two windows.
class MenuMove {
  const MenuMove({
    required this.name,
    required this.from,
    required this.to,
    required this.qty,
    required this.previousQty,
    required this.revenue,
  });

  final String name;
  final MenuClass from;
  final MenuClass to;
  final int qty;
  final int previousQty;

  /// Takings in the current window, used only to rank the moves. The dish that
  /// moved and carries the most money is the one worth the single line a
  /// headline gets.
  final int revenue;

  /// Whether the move is one a shop would have wanted.
  ///
  /// Not a linear ranking of the four classes, because there is not one: a
  /// Puzzle is not straightforwardly "better" than a Plowhorse — one is a
  /// menu-position problem, the other a pricing one. What is unambiguous is
  /// arriving at Star, and leaving Dog.
  bool get isImprovement =>
      to == MenuClass.star || (from == MenuClass.dog && to != MenuClass.dog);

  bool get isRegression =>
      to == MenuClass.dog || (from == MenuClass.star && to != MenuClass.star);
}

/// This window against the one immediately before it.
///
/// Both halves come out of a single `dailyStats` range read covering twice the
/// window, split locally. Two queries would be the same number of document
/// reads and one more round trip, and the split has to be done on the client
/// either way because the boundary is a trading date rather than a timestamp.
class WindowComparison {
  const WindowComparison({
    required this.windowDays,
    required this.current,
    required this.previous,
    required this.matrix,
    required this.previousMatrix,
    required this.currentTradingDays,
    required this.previousTradingDays,
  });

  final int windowDays;

  final DailyStats current;
  final DailyStats previous;

  final MenuEngineering matrix;
  final MenuEngineering previousMatrix;

  /// Days with any takings at all, in each half.
  final int currentTradingDays;
  final int previousTradingDays;

  /// Whether there is a previous window worth comparing against.
  ///
  /// A shop that opened six weeks ago has no comparable 90 days behind it, and
  /// the whole comparison is withheld rather than shown against zero. Half the
  /// window is the bar: below that, "down 60%" is describing when the shop
  /// opened rather than how it is trading.
  bool get hasPrevious =>
      !previous.isEmpty && previousTradingDays * 2 >= currentTradingDays;

  Comparison get revenue => Comparison(
        label: 'Takings',
        current: current.revenue.toDouble(),
        previous: previous.revenue.toDouble(),
      );

  Comparison get orders => Comparison(
        label: 'Orders',
        current: current.orderCount.toDouble(),
        previous: previous.orderCount.toDouble(),
      );

  Comparison get averageOrder => Comparison(
        label: 'Average order',
        current: current.averageOrderValue,
        previous: previous.averageOrderValue,
      );

  /// Null when either window has no costed sales to compute a rate from.
  Comparison? get foodCost {
    final now = matrix.foodCostRate;
    final before = previousMatrix.foodCostRate;
    if (now == null || before == null) return null;
    return Comparison(
      label: 'Food cost',
      current: now,
      previous: before,
      asRate: true,
    );
  }

  /// Dishes that changed quadrant, biggest earners first.
  ///
  /// Only dishes the matrix was willing to place in **both** windows. A dish
  /// that sold four plates last month and forty this one has not "moved from
  /// Dog to Star" — it was never a Dog, it was unmeasured, and reporting that
  /// as a turnaround would manufacture a success out of the sample size.
  List<MenuMove> get movers {
    final before = {
      for (final item in previousMatrix.items) item.stat.itemId: item,
    };

    final moves = <MenuMove>[];
    for (final item in matrix.items) {
      final was = before[item.stat.itemId];
      if (was == null || was.menuClass == item.menuClass) continue;
      moves.add(MenuMove(
        name: item.name,
        from: was.menuClass,
        to: item.menuClass,
        qty: item.qty,
        previousQty: was.qty,
        revenue: item.revenue,
      ));
    }

    return moves..sort((a, b) => b.revenue.compareTo(a.revenue));
  }

  /// Dishes that used to sell enough to place and no longer do.
  ///
  /// The one signal the quadrants cannot carry, because leaving the matrix is
  /// not a quadrant. A dish that was a Star last month and is now under the
  /// placement floor has not become a Dog — it has stopped selling, which is a
  /// different thing and usually a more urgent one.
  List<String> get fadedOut {
    final placedNow = {for (final item in matrix.items) item.stat.itemId};
    final thinNow = {for (final item in matrix.insufficient) item.itemId};
    return [
      for (final item in previousMatrix.items)
        if (!placedNow.contains(item.stat.itemId) &&
            thinNow.contains(item.stat.itemId))
          item.name,
    ];
  }
}
