import 'package:cloud_firestore/cloud_firestore.dart';

/// Formats a date as the `yyyy-MM-dd` string used as the id of
/// `dailyStats/{businessDate}` and `counters/{businessDate}`.
///
/// Kept as a plain string on purpose: Firestore cannot group by a Timestamp,
/// so every rollup is keyed by this.
String formatBusinessDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime parseBusinessDate(String businessDate) => DateTime.parse(businessDate);

/// A menu category. Stored inline on the store document because there are only
/// ever a handful and every screen that shows the menu needs all of them.
class StoreCategory {
  const StoreCategory({
    required this.id,
    required this.name,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final int sortOrder;

  factory StoreCategory.fromMap(Map<String, dynamic> map) => StoreCategory(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'sortOrder': sortOrder,
      };
}

/// Daily goals that drive the statistics gauge.
class StoreTargets {
  const StoreTargets({this.dailyOrders = 100, this.dailyRevenue = 20000});

  final int dailyOrders;
  final int dailyRevenue;

  factory StoreTargets.fromMap(Map<String, dynamic>? map) => StoreTargets(
        dailyOrders: (map?['dailyOrders'] as num?)?.toInt() ?? 100,
        dailyRevenue: (map?['dailyRevenue'] as num?)?.toInt() ?? 20000,
      );

  Map<String, dynamic> toMap() => {
        'dailyOrders': dailyOrders,
        'dailyRevenue': dailyRevenue,
      };
}

/// A delivery platform (UberEats, foodpanda, ...) and what it takes off the
/// top. Without the commission, delivery revenue reads far more profitable
/// than it is.
class DeliveryPlatform {
  const DeliveryPlatform({
    required this.id,
    required this.name,
    this.commissionRate = 0,
  });

  final String id;
  final String name;

  /// Fraction of the order total kept by the platform, e.g. 0.3 for 30%.
  final double commissionRate;

  factory DeliveryPlatform.fromMap(Map<String, dynamic> map) => DeliveryPlatform(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        commissionRate: (map['commissionRate'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'commissionRate': commissionRate,
      };
}

/// `stores/{storeId}`.
///
/// Deliberately holds no `totalIncome` and no `orderIndex`: cumulative revenue
/// is summed from `dailyStats`, and order numbers come from
/// `counters/{businessDate}` so two devices cannot collide on one.
class Store {
  const Store({
    required this.id,
    required this.name,
    this.currency = 'TWD',
    this.timezone = 'Asia/Taipei',
    this.taxRate = 0,
    this.taxIncluded = true,
    this.dayCutoffHour = defaultDayCutoffHour,
    this.businessHours = const {},
    this.targets = const StoreTargets(),
    this.categories = const [],
    this.deliveryPlatforms = const [],
    this.createdAt,
    this.updatedAt,
  });

  /// 04:00. An order rung up at 02:00 belongs to the previous trading day —
  /// which is how a late-night kitchen actually counts its takings. Editable
  /// per store in Store Settings.
  static const int defaultDayCutoffHour = 4;

  final String id;
  final String name;
  final String currency;
  final String timezone;

  /// Fraction, e.g. 0.05 for 5%.
  final double taxRate;

  /// True when the menu prices already contain tax (the Taiwanese default).
  final bool taxIncluded;

  /// Hour of day (0-23) at which one trading day rolls into the next.
  final int dayCutoffHour;

  final Map<String, dynamic> businessHours;
  final StoreTargets targets;
  final List<StoreCategory> categories;
  final List<DeliveryPlatform> deliveryPlatforms;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Store.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Store(
      id: doc.id,
      name: data['name'] as String? ?? '',
      currency: data['currency'] as String? ?? 'TWD',
      timezone: data['timezone'] as String? ?? 'Asia/Taipei',
      taxRate: (data['taxRate'] as num?)?.toDouble() ?? 0,
      taxIncluded: data['taxIncluded'] as bool? ?? true,
      dayCutoffHour:
          (data['dayCutoffHour'] as num?)?.toInt() ?? defaultDayCutoffHour,
      businessHours:
          Map<String, dynamic>.from(data['businessHours'] as Map? ?? const {}),
      targets: StoreTargets.fromMap(
          (data['targets'] as Map?)?.cast<String, dynamic>()),
      categories: ((data['categories'] as List?) ?? const [])
          .map((c) => StoreCategory.fromMap((c as Map).cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      deliveryPlatforms: ((data['deliveryPlatforms'] as List?) ?? const [])
          .map((p) =>
              DeliveryPlatform.fromMap((p as Map).cast<String, dynamic>()))
          .toList(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'currency': currency,
        'timezone': timezone,
        'taxRate': taxRate,
        'taxIncluded': taxIncluded,
        'dayCutoffHour': dayCutoffHour,
        'businessHours': businessHours,
        'targets': targets.toMap(),
        'categories': categories.map((c) => c.toMap()).toList(),
        'deliveryPlatforms': deliveryPlatforms.map((p) => p.toMap()).toList(),
      };

  /// The trading day a wall-clock time belongs to, as `yyyy-MM-dd`.
  String businessDateOf(DateTime at) =>
      formatBusinessDate(at.subtract(Duration(hours: dayCutoffHour)));

  /// Today's trading day.
  String get currentBusinessDate => businessDateOf(DateTime.now());

  DeliveryPlatform? platformById(String? id) {
    if (id == null) return null;
    for (final p in deliveryPlatforms) {
      if (p.id == id) return p;
    }
    return null;
  }

  String? categoryName(String? categoryId) {
    if (categoryId == null) return null;
    for (final c in categories) {
      if (c.id == categoryId) return c.name;
    }
    return null;
  }

  Store copyWith({
    String? name,
    double? taxRate,
    bool? taxIncluded,
    int? dayCutoffHour,
    StoreTargets? targets,
    List<StoreCategory>? categories,
    List<DeliveryPlatform>? deliveryPlatforms,
  }) =>
      Store(
        id: id,
        name: name ?? this.name,
        currency: currency,
        timezone: timezone,
        taxRate: taxRate ?? this.taxRate,
        taxIncluded: taxIncluded ?? this.taxIncluded,
        dayCutoffHour: dayCutoffHour ?? this.dayCutoffHour,
        businessHours: businessHours,
        targets: targets ?? this.targets,
        categories: categories ?? this.categories,
        deliveryPlatforms: deliveryPlatforms ?? this.deliveryPlatforms,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
