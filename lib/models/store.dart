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

/// A way a customer is allowed to pay, as this shop actually takes money.
///
/// Was a fixed `enum PaymentMethod` — cash, credit card, Line Pay, other —
/// which is one developer's guess at a Taiwanese street kitchen's till and
/// wrong for everyone else: a shop taking 街口支付, 悠遊卡, 振興券 or a monthly
/// account had to file all of them under "Other" and then had a payment
/// breakdown that said nothing. Stored inline on the store document, like
/// [StoreCategory], because every screen that shows an order needs the whole
/// list at once.
///
/// [id] is what goes on the order and what keys `dailyStats.byPayment`, so it
/// is generated once and never rewritten — renaming a method relabels its
/// history rather than splitting it in two.
class StorePaymentMethod {
  const StorePaymentMethod({
    required this.id,
    required this.name,
    this.iconKey,
    this.sortOrder = 0,
  });

  final String id;
  final String name;

  /// A key into `kPaymentIcons`, not a code point. See `payment_icons.dart`
  /// for why the icons are a fixed, `const` list.
  final String? iconKey;

  final int sortOrder;

  factory StorePaymentMethod.fromMap(Map<String, dynamic> map) =>
      StorePaymentMethod(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        iconKey: map['iconKey'] as String?,
        sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'iconKey': iconKey,
    'sortOrder': sortOrder,
  };

  StorePaymentMethod copyWith({
    String? name,
    String? iconKey,
    int? sortOrder,
  }) => StorePaymentMethod(
    id: id,
    name: name ?? this.name,
    iconKey: iconKey ?? this.iconKey,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}

/// What a store takes until somebody edits the list.
///
/// The ids match the ones the old enum wrote, so every order and every
/// `byPayment` bucket already in Firestore keeps its label.
const List<StorePaymentMethod> kDefaultPaymentMethods = [
  StorePaymentMethod(id: 'cash', name: 'Cash', iconKey: 'cash'),
  StorePaymentMethod(
    id: 'credit_card',
    name: 'Credit card',
    iconKey: 'card',
    sortOrder: 1,
  ),
  StorePaymentMethod(
    id: 'line_pay',
    name: 'Line Pay',
    iconKey: 'contactless',
    sortOrder: 2,
  ),
  StorePaymentMethod(id: 'other', name: 'Other', iconKey: 'more', sortOrder: 3),
];

/// The method an id refers to, or a stand-in that carries the id's own words.
///
/// Never null and never silently "Cash": an order paid by a method the shop has
/// since deleted has to keep reading as that method, or a month of history
/// quietly moves into the wrong column.
StorePaymentMethod resolvePaymentMethod(
  List<StorePaymentMethod> methods,
  String? id,
) {
  if (id == null || id.isEmpty) return methods.first;
  for (final method in methods) {
    if (method.id == id) return method;
  }
  for (final method in kDefaultPaymentMethods) {
    if (method.id == id) return method;
  }
  return StorePaymentMethod(id: id, name: _prettifyId(id), iconKey: 'more');
}

/// `line_pay` -> `Line pay`. Only ever seen for a method that was deleted
/// before this store's list was edited, which is better than showing the id.
String _prettifyId(String id) {
  final words = id.replaceAll('_', ' ').trim();
  if (words.isEmpty) return id;
  return words[0].toUpperCase() + words.substring(1);
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

  factory DeliveryPlatform.fromMap(Map<String, dynamic> map) =>
      DeliveryPlatform(
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
    this.idleTimeoutMinutes = 0,
    this.businessHours = const {},
    this.targets = const StoreTargets(),
    this.categories = const [],
    this.paymentMethods = kDefaultPaymentMethods,
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

  /// Minutes of no touching before the till returns to the operator picker.
  /// Zero is off, which is the default.
  ///
  /// Per store rather than per device, because it is a rule about how the shop
  /// runs its counter rather than about the hardware. It does not sign anybody
  /// out — see IdleLock for why that would cost more than it protects.
  final int idleTimeoutMinutes;

  final Map<String, dynamic> businessHours;
  final StoreTargets targets;
  final List<StoreCategory> categories;

  /// Never empty: a store whose document predates this field, or whose list
  /// somehow got emptied, falls back to [kDefaultPaymentMethods] so the till
  /// always has something to ring an order up against.
  final List<StorePaymentMethod> paymentMethods;

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
      // Clamped, because this ends up as a dropdown's value and a dropdown
      // asserts fatally on a value it has no item for. A hand-edited document
      // holding 25 would make Store Settings unopenable.
      dayCutoffHour:
          ((data['dayCutoffHour'] as num?)?.toInt() ?? defaultDayCutoffHour)
              .clamp(0, 23),
      // Clamped for the same reason as the cut-off: this drives a dropdown,
      // and an hour-long timeout is already past the point of being one.
      idleTimeoutMinutes:
          ((data['idleTimeoutMinutes'] as num?)?.toInt() ?? 0).clamp(0, 60),
      businessHours: Map<String, dynamic>.from(
        data['businessHours'] as Map? ?? const {},
      ),
      targets: StoreTargets.fromMap(
        (data['targets'] as Map?)?.cast<String, dynamic>(),
      ),
      categories:
          ((data['categories'] as List?) ?? const [])
              .map(
                (c) =>
                    StoreCategory.fromMap((c as Map).cast<String, dynamic>()),
              )
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      paymentMethods: _paymentMethodsFrom(data['paymentMethods'] as List?),
      deliveryPlatforms: ((data['deliveryPlatforms'] as List?) ?? const [])
          .map(
            (p) => DeliveryPlatform.fromMap((p as Map).cast<String, dynamic>()),
          )
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
    'idleTimeoutMinutes': idleTimeoutMinutes,
    'businessHours': businessHours,
    'targets': targets.toMap(),
    'categories': categories.map((c) => c.toMap()).toList(),
    'paymentMethods': paymentMethods.map((p) => p.toMap()).toList(),
    'deliveryPlatforms': deliveryPlatforms.map((p) => p.toMap()).toList(),
  };

  /// The trading day a wall-clock time belongs to, as `yyyy-MM-dd`.
  String businessDateOf(DateTime at) =>
      formatBusinessDate(at.subtract(Duration(hours: dayCutoffHour)));

  /// Today's trading day.
  String get currentBusinessDate => businessDateOf(DateTime.now());

  /// The payment method an order's stored id refers to. See
  /// [resolvePaymentMethod] for what happens to a deleted one.
  StorePaymentMethod paymentMethodById(String? id) =>
      resolvePaymentMethod(paymentMethods, id);

  /// What a fresh order starts on.
  String get defaultPaymentMethodId => paymentMethods.first.id;

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
    int? idleTimeoutMinutes,
    StoreTargets? targets,
    List<StoreCategory>? categories,
    List<StorePaymentMethod>? paymentMethods,
    List<DeliveryPlatform>? deliveryPlatforms,
  }) => Store(
    id: id,
    name: name ?? this.name,
    currency: currency,
    timezone: timezone,
    taxRate: taxRate ?? this.taxRate,
    taxIncluded: taxIncluded ?? this.taxIncluded,
    dayCutoffHour: dayCutoffHour ?? this.dayCutoffHour,
    idleTimeoutMinutes: idleTimeoutMinutes ?? this.idleTimeoutMinutes,
    businessHours: businessHours,
    targets: targets ?? this.targets,
    categories: categories ?? this.categories,
    paymentMethods: paymentMethods ?? this.paymentMethods,
    deliveryPlatforms: deliveryPlatforms ?? this.deliveryPlatforms,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Reads the stored payment methods, falling back to the defaults.
///
/// An empty list is treated as "never set", not as "this shop takes no money":
/// the till has to offer something, and the settings screen refuses to delete
/// the last method for the same reason.
List<StorePaymentMethod> _paymentMethodsFrom(List<dynamic>? raw) {
  final methods =
      (raw ?? const [])
          .map(
            (p) =>
                StorePaymentMethod.fromMap((p as Map).cast<String, dynamic>()),
          )
          .where((p) => p.id.isNotEmpty)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return methods.isEmpty ? kDefaultPaymentMethods : methods;
}
