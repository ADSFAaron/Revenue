import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/daily_stats.dart';
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

/// Reads `stores/{storeId}/dailyStats/{businessDate}`.
///
/// Every Day / Week / Month view reads from here rather than from `orders`:
/// a month is 30 document reads instead of a few thousand, and there is no
/// arithmetic left for the phone to do.
class StatsRepository {
  StatsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _stats(String storeId) =>
      _db.collection('stores').doc(storeId).collection('dailyStats');

  Future<DailyStats?> fetchDay(String storeId, String businessDate) async {
    final doc = await _stats(storeId).doc(businessDate).get();
    return doc.exists ? DailyStats.fromDoc(doc) : null;
  }

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
    final snap = await _rangeQuery(storeId, fromBusinessDate, toBusinessDate)
        .get();
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

  /// The trading days either side of [businessDate], for the statistics page's
  /// back / forward arrows.
  static String shiftBusinessDate(String businessDate, int days) =>
      formatBusinessDate(parseBusinessDate(businessDate)
          .add(Duration(days: days)));
}
