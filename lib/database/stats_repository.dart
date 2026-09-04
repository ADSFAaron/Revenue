import 'package:cloud_firestore/cloud_firestore.dart';

import 'session_apps.dart';

import '../models/daily_stats.dart';
import '../models/stats_period.dart';
import '../models/store.dart';

/// All-time figures for a store.
class StoreTotals {
  const StoreTotals({this.revenue = 0, this.orderCount = 0, this.days = 0});

  final int revenue;
  final int orderCount;

  /// How many trading days the store has taken money on.
  final int days;

  double get averageOrderValue => orderCount == 0 ? 0 : revenue / orderCount;
}

/// A period's takings next to the comparable stretch of the period before it.
///
/// Both halves are carried together because a figure on its own does not tell a
/// shop owner anything: NT$18,000 is a good Tuesday or a bad one depending
/// entirely on what last Tuesday did.
class PeriodReport {
  const PeriodReport({
    required this.period,
    required this.days,
    required this.total,
    required this.previousTotal,
    required this.previousPeriod,
  });

  final StatsPeriod period;

  /// The individual trading days, oldest first — only the days that have any
  /// takings exist as documents, so this is usually shorter than the period.
  final List<DailyStats> days;

  final DailyStats total;
  final DailyStats previousTotal;

  /// The stretch [previousTotal] covers, which for an unfinished period is
  /// shorter than a whole one. See [StatsPeriod.comparableTo].
  final StatsPeriod previousPeriod;

  bool get isEmpty => total.isEmpty;

  /// Fractional change against the previous period, e.g. 0.12 for +12%.
  ///
  /// Null when the previous period took nothing: there is no percentage change
  /// from zero, and showing "+100%" for a store's first day of trading — or
  /// after a week's holiday — is worse than showing nothing.
  static double? change(num current, num previous) {
    if (previous == 0) return null;
    return (current - previous) / previous;
  }
}

/// Reads `stores/{storeId}/dailyStats/{businessDate}`.
///
/// Every Day / Week / Month view reads from here rather than from `orders`:
/// a month is 30 document reads instead of a few thousand, and there is no
/// arithmetic left for the phone to do.
class StatsRepository {
  StatsRepository({FirebaseFirestore? firestore})
      : _injected = firestore;

  final FirebaseFirestore? _injected;

  /// Read through the session that is current, not captured once.
  ///
  /// A counter tablet can hold several operators signed in at the same time,
  /// one Firebase app each, and handing the till over swaps which of them is
  /// current. A handle captured in the constructor would keep answering as the
  /// person who was at the till when this object was built. See SessionApps.
  FirebaseFirestore get _db =>
      _injected ?? FirebaseFirestore.instanceFor(app: sessionApps.active);

  CollectionReference<Map<String, dynamic>> _stats(String storeId) =>
      _db.collection('stores').doc(storeId).collection('dailyStats');

  Stream<DailyStats> watchDay(String storeId, String businessDate) =>
      _stats(storeId).doc(businessDate).snapshots().map((doc) => doc.exists
          ? DailyStats.fromDoc(doc)
          : DailyStats(businessDate: businessDate));

  /// Inclusive range of trading days, oldest first.
  Future<List<DailyStats>> fetchRange(
    String storeId, {
    required String fromBusinessDate,
    required String toBusinessDate,
  }) async {
    final snap =
        await _rangeQuery(storeId, fromBusinessDate, toBusinessDate).get();
    return snap.docs.map(DailyStats.fromDoc).toList();
  }

  Stream<List<DailyStats>> watchRange(
    String storeId, {
    required String fromBusinessDate,
    required String toBusinessDate,
  }) =>
      _rangeQuery(storeId, fromBusinessDate, toBusinessDate)
          .snapshots()
          .map((snap) => snap.docs.map(DailyStats.fromDoc).toList());

  Query<Map<String, dynamic>> _rangeQuery(
          String storeId, String from, String to) =>
      _stats(storeId)
          .where('businessDate', isGreaterThanOrEqualTo: from)
          .where('businessDate', isLessThanOrEqualTo: to)
          .orderBy('businessDate');

  /// A range already added up, for a week or month card.
  Future<DailyStats> fetchRangeTotal(
    String storeId, {
    required String fromBusinessDate,
    required String toBusinessDate,
  }) async {
    final days = await fetchRange(storeId,
        fromBusinessDate: fromBusinessDate, toBusinessDate: toBusinessDate);
    return DailyStats.sum(days, label: '$fromBusinessDate..$toBusinessDate');
  }

  /// Lifetime revenue and order count.
  ///
  /// Uses a Firestore aggregation query, so this costs a handful of reads
  /// rather than one per trading day — which is what made the old cumulative
  /// `totalIncome` counter on the store document tempting in the first place.
  Future<StoreTotals> fetchTotals(String storeId) async {
    final snap = await _stats(storeId)
        .aggregate(sum('revenue'), sum('orderCount'), count())
        .get();
    return StoreTotals(
      revenue: (snap.getSum('revenue') ?? 0).round(),
      orderCount: (snap.getSum('orderCount') ?? 0).round(),
      days: snap.count ?? 0,
    );
  }

  /// A period's rollup together with the previous period's, for the statistics
  /// page.
  ///
  /// The current range is watched — the Day view has to move while the till is
  /// still ringing — but the comparison is fetched once. A period that has
  /// already finished cannot change, and re-reading it on every order would
  /// double the page's cost for no new information.
  Stream<PeriodReport> watchPeriod(
    String storeId,
    StatsPeriod period, {
    required DateTime today,
  }) async* {
    final previousPeriod = period.comparableTo(today);
    final previousTotal = await fetchRangeTotal(
      storeId,
      fromBusinessDate: previousPeriod.fromBusinessDate,
      toBusinessDate: previousPeriod.toBusinessDate,
    );

    yield* watchRange(
      storeId,
      fromBusinessDate: period.fromBusinessDate,
      toBusinessDate: period.toBusinessDate,
    ).map((days) => PeriodReport(
          period: period,
          days: days,
          total: DailyStats.sum(days, label: period.toString()),
          previousTotal: previousTotal,
          previousPeriod: previousPeriod,
        ));
  }

  /// The trading days either side of [businessDate], for the statistics page's
  /// back / forward arrows.
  static String shiftBusinessDate(String businessDate, int days) =>
      formatBusinessDate(
          parseBusinessDate(businessDate).add(Duration(days: days)));
}
