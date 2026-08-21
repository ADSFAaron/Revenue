import 'order.dart';
import 'store.dart';

/// The money side of an order, computed in one place so the total the till
/// shows and the total that gets written can never disagree.
class OrderTotals {
  const OrderTotals({
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.total,
    required this.totalCost,
    required this.commissionAmount,
  });

  final int subtotal;
  final int discountAmount;

  /// The tax contained in (or added to) [total], depending on
  /// [Store.taxIncluded].
  final int taxAmount;
  final int total;
  final int totalCost;
  final int commissionAmount;

  int get grossProfit => total - totalCost - commissionAmount;
}

/// An order being composed at the till, before it has an id or a number.
class OrderDraft {
  const OrderDraft({
    required this.placedAt,
    required this.items,
    this.channel = OrderChannel.dineIn,
    this.guestCount = 1,
    this.deliveryPlatformId,
    this.paymentMethod = PaymentMethod.cash,
    this.discountAmount = 0,
    this.discountReason,
  });

  final DateTime placedAt;
  final List<OrderLine> items;
  final OrderChannel channel;
  final int guestCount;
  final String? deliveryPlatformId;
  final PaymentMethod paymentMethod;
  final int discountAmount;
  final String? discountReason;

  bool get isEmpty => items.isEmpty;

  /// Prices the draft against the store's tax rate and, for delivery, the
  /// platform's commission.
  ///
  /// Taiwanese menu prices normally already contain tax, so [Store.taxIncluded]
  /// decides whether tax is carved out of the total or added on top.
  OrderTotals price(Store store) {
    final subtotal = items.fold<int>(0, (acc, i) => acc + i.lineRevenue);
    final totalCost = items.fold<int>(0, (acc, i) => acc + i.lineCost);
    final discount = discountAmount.clamp(0, subtotal);
    final net = subtotal - discount;

    final int total;
    final int taxAmount;
    if (store.taxRate <= 0) {
      total = net;
      taxAmount = 0;
    } else if (store.taxIncluded) {
      total = net;
      taxAmount = (net * store.taxRate / (1 + store.taxRate)).round();
    } else {
      taxAmount = (net * store.taxRate).round();
      total = net + taxAmount;
    }

    final commissionRate = channel == OrderChannel.delivery
        ? (store.platformById(deliveryPlatformId)?.commissionRate ?? 0)
        : 0.0;

    return OrderTotals(
      subtotal: subtotal,
      discountAmount: discount,
      taxAmount: taxAmount,
      total: total,
      totalCost: totalCost,
      commissionAmount: (total * commissionRate).round(),
    );
  }

  /// Builds the document to persist. [orderNo] comes from the day's counter and
  /// [id] from the pre-allocated Firestore reference.
  Order toOrder({
    required String id,
    required int orderNo,
    required Store store,
    String? createdBy,
  }) {
    final totals = price(store);
    final commissionRate = channel == OrderChannel.delivery
        ? (store.platformById(deliveryPlatformId)?.commissionRate ?? 0)
        : 0.0;

    return Order(
      id: id,
      orderNo: orderNo,
      businessDate: store.businessDateOf(placedAt),
      placedAt: placedAt,
      hourOfDay: placedAt.hour,
      weekday: placedAt.weekday,
      channel: channel,
      guestCount: guestCount,
      deliveryPlatformId:
          channel == OrderChannel.delivery ? deliveryPlatformId : null,
      commissionRate: commissionRate,
      commissionAmount: totals.commissionAmount,
      paymentMethod: paymentMethod,
      items: items,
      subtotal: totals.subtotal,
      discountAmount: totals.discountAmount,
      discountReason: discountReason,
      taxAmount: totals.taxAmount,
      total: totals.total,
      totalCost: totals.totalCost,
      createdBy: createdBy,
    );
  }

  /// Rebuilds a draft from a stored order, for the edit screen.
  factory OrderDraft.fromOrder(Order order) => OrderDraft(
        placedAt: order.placedAt,
        items: order.items,
        channel: order.channel,
        guestCount: order.guestCount,
        deliveryPlatformId: order.deliveryPlatformId,
        paymentMethod: order.paymentMethod,
        discountAmount: order.discountAmount,
        discountReason: order.discountReason,
      );

  OrderDraft copyWith({
    DateTime? placedAt,
    List<OrderLine>? items,
    OrderChannel? channel,
    int? guestCount,
    String? deliveryPlatformId,
    bool clearDeliveryPlatform = false,
    PaymentMethod? paymentMethod,
    int? discountAmount,
    String? discountReason,
  }) =>
      OrderDraft(
        placedAt: placedAt ?? this.placedAt,
        items: items ?? this.items,
        channel: channel ?? this.channel,
        guestCount: guestCount ?? this.guestCount,
        deliveryPlatformId: clearDeliveryPlatform
            ? null
            : (deliveryPlatformId ?? this.deliveryPlatformId),
        paymentMethod: paymentMethod ?? this.paymentMethod,
        discountAmount: discountAmount ?? this.discountAmount,
        discountReason: discountReason ?? this.discountReason,
      );
}
