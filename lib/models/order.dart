import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// How the order reached the customer. Kept separate from payment method
/// because the cost structures differ completely — packaging on takeout,
/// platform commission on delivery.
enum OrderChannel {
  dineIn('dine_in', 'Dine-in', Icons.restaurant_rounded),
  takeout('takeout', 'Takeout', Icons.takeout_dining_rounded),
  delivery('delivery', 'Delivery', Icons.delivery_dining_rounded);

  const OrderChannel(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  static OrderChannel fromId(String? id) => OrderChannel.values
      .firstWhere((c) => c.id == id, orElse: () => OrderChannel.dineIn);
}

enum PaymentMethod {
  cash('cash', 'Cash', Icons.money_rounded),
  creditCard('credit_card', 'Credit Card', Icons.credit_card_rounded),
  linePay('line_pay', 'Line Pay', Icons.contactless_rounded),
  other('other', 'Other', Icons.more_horiz_rounded);

  const PaymentMethod(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  static PaymentMethod fromId(String? id) => PaymentMethod.values
      .firstWhere((p) => p.id == id, orElse: () => PaymentMethod.cash);
}

enum OrderStatus {
  completed('completed'),
  voided('voided');

  const OrderStatus(this.id);

  final String id;

  static OrderStatus fromId(String? id) => OrderStatus.values
      .firstWhere((s) => s.id == id, orElse: () => OrderStatus.completed);
}

/// One line on an order.
///
/// `name`, `unitPrice` and `unitCost` are copied in on purpose. A historical
/// order has to freeze the numbers as they were at the till — otherwise a price
/// rise or a new supplier quietly rewrites every past month's profit report.
class OrderLine {
  const OrderLine({
    required this.itemId,
    required this.name,
    this.categoryId,
    required this.unitPrice,
    this.unitCost = 0,
    required this.qty,
    this.note,
  });

  final String itemId;
  final String name;
  final String? categoryId;
  final int unitPrice;
  final int unitCost;
  final int qty;
  final String? note;

  int get lineRevenue => unitPrice * qty;
  int get lineCost => unitCost * qty;
  int get lineProfit => lineRevenue - lineCost;

  factory OrderLine.fromMap(Map<String, dynamic> map) => OrderLine(
        itemId: map['itemId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        categoryId: map['categoryId'] as String?,
        unitPrice: (map['unitPrice'] as num?)?.toInt() ?? 0,
        unitCost: (map['unitCost'] as num?)?.toInt() ?? 0,
        qty: (map['qty'] as num?)?.toInt() ?? 0,
        note: map['note'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'itemId': itemId,
        'name': name,
        'categoryId': categoryId,
        'unitPrice': unitPrice,
        'unitCost': unitCost,
        'qty': qty,
        'lineRevenue': lineRevenue,
        'lineCost': lineCost,
        'note': note,
      };

  OrderLine copyWith({int? qty}) => OrderLine(
        itemId: itemId,
        name: name,
        categoryId: categoryId,
        unitPrice: unitPrice,
        unitCost: unitCost,
        qty: qty ?? this.qty,
        note: note,
      );
}

/// `stores/{storeId}/orders/{orderId}` — one document per order.
///
/// `businessDate`, `hourOfDay` and `weekday` are redundant against `placedAt`
/// and are stored anyway: Firestore has no `EXTRACT(HOUR FROM ...)`, so without
/// them every time-of-day report would have to download the whole history and
/// compute it on the phone.
class Order {
  const Order({
    required this.id,
    required this.orderNo,
    required this.businessDate,
    required this.placedAt,
    required this.hourOfDay,
    required this.weekday,
    this.channel = OrderChannel.dineIn,
    this.guestCount = 1,
    this.deliveryPlatformId,
    this.commissionRate = 0,
    this.commissionAmount = 0,
    this.paymentMethod = PaymentMethod.cash,
    this.items = const [],
    this.subtotal = 0,
    this.discountAmount = 0,
    this.discountReason,
    this.taxAmount = 0,
    this.total = 0,
    this.totalCost = 0,
    this.status = OrderStatus.completed,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final int orderNo;

  /// `yyyy-MM-dd`, already shifted by the store's `dayCutoffHour`.
  final String businessDate;
  final DateTime placedAt;

  /// 0-23.
  final int hourOfDay;

  /// 1 = Monday .. 7 = Sunday, matching [DateTime.weekday].
  final int weekday;

  final OrderChannel channel;
  final int guestCount;
  final String? deliveryPlatformId;
  final double commissionRate;
  final int commissionAmount;
  final PaymentMethod paymentMethod;
  final List<OrderLine> items;

  final int subtotal;
  final int discountAmount;
  final String? discountReason;
  final int taxAmount;
  final int total;
  final int totalCost;

  final OrderStatus status;
  final DateTime? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Profit after ingredient cost and platform commission.
  int get grossProfit => total - totalCost - commissionAmount;

  bool get isVoided => status == OrderStatus.voided;

  List<String> get itemIds =>
      items.map((i) => i.itemId).where((id) => id.isNotEmpty).toSet().toList();

  int get itemQty => items.fold(0, (total, i) => total + i.qty);

  factory Order.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Order.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});

  factory Order.fromMap(String id, Map<String, dynamic> data) {
    final placedAt =
        (data['placedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return Order(
      id: id,
      orderNo: (data['orderNo'] as num?)?.toInt() ?? 0,
      businessDate: data['businessDate'] as String? ?? '',
      placedAt: placedAt,
      hourOfDay: (data['hourOfDay'] as num?)?.toInt() ?? placedAt.hour,
      weekday: (data['weekday'] as num?)?.toInt() ?? placedAt.weekday,
      channel: OrderChannel.fromId(data['channel'] as String?),
      guestCount: (data['guestCount'] as num?)?.toInt() ?? 1,
      deliveryPlatformId: data['deliveryPlatformId'] as String?,
      commissionRate: (data['commissionRate'] as num?)?.toDouble() ?? 0,
      commissionAmount: (data['commissionAmount'] as num?)?.toInt() ?? 0,
      paymentMethod: PaymentMethod.fromId(data['paymentMethod'] as String?),
      items: ((data['items'] as List?) ?? const [])
          .map((i) => OrderLine.fromMap((i as Map).cast<String, dynamic>()))
          .toList(),
      subtotal: (data['subtotal'] as num?)?.toInt() ?? 0,
      discountAmount: (data['discountAmount'] as num?)?.toInt() ?? 0,
      discountReason: data['discountReason'] as String?,
      taxAmount: (data['taxAmount'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? 0,
      totalCost: (data['totalCost'] as num?)?.toInt() ?? 0,
      status: OrderStatus.fromId(data['status'] as String?),
      voidedAt: (data['voidedAt'] as Timestamp?)?.toDate(),
      voidedBy: data['voidedBy'] as String?,
      voidReason: data['voidReason'] as String?,
      createdBy: data['createdBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'orderNo': orderNo,
        'businessDate': businessDate,
        'placedAt': Timestamp.fromDate(placedAt),
        'hourOfDay': hourOfDay,
        'weekday': weekday,
        'channel': channel.id,
        'guestCount': guestCount,
        'deliveryPlatformId': deliveryPlatformId,
        'commissionRate': commissionRate,
        'commissionAmount': commissionAmount,
        'paymentMethod': paymentMethod.id,
        'items': items.map((i) => i.toMap()).toList(),
        'itemIds': itemIds,
        'subtotal': subtotal,
        'discountAmount': discountAmount,
        'discountReason': discountReason,
        'taxAmount': taxAmount,
        'total': total,
        'totalCost': totalCost,
        'grossProfit': grossProfit,
        'status': status.id,
        'voidedAt': voidedAt == null ? null : Timestamp.fromDate(voidedAt!),
        'voidedBy': voidedBy,
        'voidReason': voidReason,
        'createdBy': createdBy,
      };
}
