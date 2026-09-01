import 'package:cloud_firestore/cloud_firestore.dart';

/// One bucket of a `by*` breakdown: hour of day, channel or payment method.
class StatBucket {
  const StatBucket({this.orders = 0, this.revenue = 0, this.guests = 0});

  final int orders;
  final int revenue;
  final int guests;

  factory StatBucket.fromMap(Map<String, dynamic> map) => StatBucket(
        orders: (map['orders'] as num?)?.toInt() ?? 0,
        revenue: (map['revenue'] as num?)?.toInt() ?? 0,
        guests: (map['guests'] as num?)?.toInt() ?? 0,
      );
}

/// One dish's contribution on a given trading day.
class ItemStat {
  const ItemStat({
    required this.itemId,
    required this.name,
    this.qty = 0,
    this.revenue = 0,
    this.cost = 0,
  });

  final String itemId;
  final String name;
  final int qty;
  final int revenue;
  final int cost;

  int get profit => revenue - cost;

  /// Null when the dish has no cost filled in — an unknown margin must not be
  /// reported as a 100% margin.
  double? get marginRate {
    if (cost <= 0 || revenue <= 0) return null;
    return profit / revenue;
  }

  factory ItemStat.fromMap(String itemId, Map<String, dynamic> map) => ItemStat(
        itemId: itemId,
        name: map['name'] as String? ?? '',
        qty: (map['qty'] as num?)?.toInt() ?? 0,
        revenue: (map['revenue'] as num?)?.toInt() ?? 0,
        cost: (map['cost'] as num?)?.toInt() ?? 0,
      );
}

class CategoryStat {
  const CategoryStat({
    required this.categoryId,
    this.qty = 0,
    this.revenue = 0,
    this.cost = 0,
  });

  final String categoryId;
  final int qty;
  final int revenue;
  final int cost;

  int get profit => revenue - cost;

  factory CategoryStat.fromMap(String categoryId, Map<String, dynamic> map) =>
      CategoryStat(
        categoryId: categoryId,
        qty: (map['qty'] as num?)?.toInt() ?? 0,
        revenue: (map['revenue'] as num?)?.toInt() ?? 0,
        cost: (map['cost'] as num?)?.toInt() ?? 0,
      );
}

/// `stores/{storeId}/dailyStats/{businessDate}` — the pre-aggregated rollup.
///
/// This document exists because Firestore has no GROUP BY and bills per
/// document read. A month's report is 30 reads here versus a few thousand
/// against `orders`, and the phone does no heavy arithmetic either way.
///
/// It is maintained by the same transaction that writes the order, using
/// [FieldValue.increment] so two devices ringing up at once cannot lose a sale.
class DailyStats {
  const DailyStats({
    required this.businessDate,
    this.orderCount = 0,
    this.guestCount = 0,
    this.voidedCount = 0,
    this.revenue = 0,
    this.cost = 0,
    this.discountTotal = 0,
    this.taxTotal = 0,
    this.commissionTotal = 0,
    this.byHour = const {},
    this.byChannel = const {},
    this.byPayment = const {},
    this.byItem = const {},
    this.byCategory = const {},
    this.updatedAt,
  });

  final String businessDate;
  final int orderCount;
  final int guestCount;
  final int voidedCount;
  final int revenue;
  final int cost;
  final int discountTotal;
  final int taxTotal;
  final int commissionTotal;

  /// Keyed by hour of day as a string, '0'..'23'.
  final Map<String, StatBucket> byHour;

  /// Keyed by [OrderChannel.id].
  final Map<String, StatBucket> byChannel;

  /// Keyed by [StorePaymentMethod.id].
  final Map<String, StatBucket> byPayment;

  final Map<String, ItemStat> byItem;
  final Map<String, CategoryStat> byCategory;
  final DateTime? updatedAt;

  int get grossProfit => revenue - cost - commissionTotal;

  /// Average spend per order.
  double get averageOrderValue => orderCount == 0 ? 0 : revenue / orderCount;

  /// Average spend per head — the number that actually moves when a family of
  /// four shares one bill.
  double get averageGuestSpend => guestCount == 0 ? 0 : revenue / guestCount;

  bool get isEmpty => orderCount == 0 && voidedCount == 0;

  factory DailyStats.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    Map<String, StatBucket> buckets(String key) =>
        ((data[key] as Map?) ?? const {}).map((k, v) => MapEntry(k as String,
            StatBucket.fromMap((v as Map).cast<String, dynamic>())));

    return DailyStats(
      businessDate: data['businessDate'] as String? ?? doc.id,
      orderCount: (data['orderCount'] as num?)?.toInt() ?? 0,
      guestCount: (data['guestCount'] as num?)?.toInt() ?? 0,
      voidedCount: (data['voidedCount'] as num?)?.toInt() ?? 0,
      revenue: (data['revenue'] as num?)?.toInt() ?? 0,
      cost: (data['cost'] as num?)?.toInt() ?? 0,
      discountTotal: (data['discountTotal'] as num?)?.toInt() ?? 0,
      taxTotal: (data['taxTotal'] as num?)?.toInt() ?? 0,
      commissionTotal: (data['commissionTotal'] as num?)?.toInt() ?? 0,
      byHour: buckets('byHour'),
      byChannel: buckets('byChannel'),
      byPayment: buckets('byPayment'),
      byItem: ((data['byItem'] as Map?) ?? const {}).map((k, v) => MapEntry(
          k as String,
          ItemStat.fromMap(k, (v as Map).cast<String, dynamic>()))),
      byCategory: ((data['byCategory'] as Map?) ?? const {}).map((k, v) =>
          MapEntry(k as String,
              CategoryStat.fromMap(k, (v as Map).cast<String, dynamic>()))),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Dishes ranked by units sold, best first.
  List<ItemStat> get itemsByQty {
    final list = byItem.values.toList()..sort((a, b) => b.qty.compareTo(a.qty));
    return list;
  }

  /// Dishes ranked by revenue, best first.
  List<ItemStat> get itemsByRevenue {
    final list = byItem.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    return list;
  }

  /// Adds several trading days together for the week and month views.
  static DailyStats sum(Iterable<DailyStats> days, {String label = ''}) {
    var orderCount = 0,
        guestCount = 0,
        voidedCount = 0,
        revenue = 0,
        cost = 0,
        discountTotal = 0,
        taxTotal = 0,
        commissionTotal = 0;
    final byHour = <String, StatBucket>{};
    final byChannel = <String, StatBucket>{};
    final byPayment = <String, StatBucket>{};
    final byItem = <String, ItemStat>{};
    final byCategory = <String, CategoryStat>{};

    void mergeBuckets(
        Map<String, StatBucket> into, Map<String, StatBucket> from) {
      from.forEach((key, bucket) {
        final existing = into[key];
        into[key] = StatBucket(
          orders: (existing?.orders ?? 0) + bucket.orders,
          revenue: (existing?.revenue ?? 0) + bucket.revenue,
          guests: (existing?.guests ?? 0) + bucket.guests,
        );
      });
    }

    for (final day in days) {
      orderCount += day.orderCount;
      guestCount += day.guestCount;
      voidedCount += day.voidedCount;
      revenue += day.revenue;
      cost += day.cost;
      discountTotal += day.discountTotal;
      taxTotal += day.taxTotal;
      commissionTotal += day.commissionTotal;
      mergeBuckets(byHour, day.byHour);
      mergeBuckets(byChannel, day.byChannel);
      mergeBuckets(byPayment, day.byPayment);

      day.byItem.forEach((id, stat) {
        final existing = byItem[id];
        byItem[id] = ItemStat(
          itemId: id,
          name: stat.name.isNotEmpty ? stat.name : (existing?.name ?? ''),
          qty: (existing?.qty ?? 0) + stat.qty,
          revenue: (existing?.revenue ?? 0) + stat.revenue,
          cost: (existing?.cost ?? 0) + stat.cost,
        );
      });

      day.byCategory.forEach((id, stat) {
        final existing = byCategory[id];
        byCategory[id] = CategoryStat(
          categoryId: id,
          qty: (existing?.qty ?? 0) + stat.qty,
          revenue: (existing?.revenue ?? 0) + stat.revenue,
          cost: (existing?.cost ?? 0) + stat.cost,
        );
      });
    }

    return DailyStats(
      businessDate: label,
      orderCount: orderCount,
      guestCount: guestCount,
      voidedCount: voidedCount,
      revenue: revenue,
      cost: cost,
      discountTotal: discountTotal,
      taxTotal: taxTotal,
      commissionTotal: commissionTotal,
      byHour: byHour,
      byChannel: byChannel,
      byPayment: byPayment,
      byItem: byItem,
      byCategory: byCategory,
    );
  }
}
