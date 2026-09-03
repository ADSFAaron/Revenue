import 'dart:convert';

import 'order.dart';
import 'order_draft.dart';

/// An order rung up while the till had no connection, waiting on this device.
///
/// **Why this exists.** An order number comes out of a Firestore transaction
/// (`counters/{businessDate}.nextOrderNo`), and a transaction is the one write
/// Firestore's offline queue will not hold — it has to read the server's value
/// first. So a dropped connection used to stop the till dead: the basket
/// survived, but nothing could be saved until the wifi came back, with a
/// customer standing there.
///
/// The order is therefore kept here, on the device, exactly as it was rung up,
/// and sent when there is a connection again. What matters is what it keeps:
///
///  * [OrderDraft.placedAt] — the moment it was *rung up*, not the moment it
///    was sent. Otherwise a lunch order sent at four in the afternoon lands in
///    the wrong hour, and across the 04:00 cutoff in the wrong trading day.
///  * The prices, which `OrderLine` already froze at ring-up time.
///  * [id] — the Firestore document id, allocated on this device before the
///    order is queued. Sending is then idempotent: a flush interrupted between
///    the commit and the queue being cleaned up writes to the same document
///    the second time, and the transaction can see it is already there rather
///    than ringing the sale up twice.
class PendingOrder {
  const PendingOrder({
    required this.id,
    required this.storeId,
    required this.queuedAt,
    required this.draft,
    this.createdBy,
  });

  /// The Firestore document id this order will take. Client-generated, which
  /// Firestore supports offline.
  final String id;

  final String storeId;

  /// When it went into the queue — for the "waiting since 14:32" line. The
  /// order's own time is [OrderDraft.placedAt].
  final DateTime queuedAt;

  final OrderDraft draft;

  /// Who rang it up, captured here rather than read at send time.
  ///
  /// [PendingOrderQueue.flush] used to call `submit()` without a `createdBy`
  /// at all, so every order taken offline reached Firestore with the field
  /// null — on precisely the path where knowing who served the customer
  /// matters most, since a counter shared across a shift is where the question
  /// gets asked.
  ///
  /// Reading the signed-in user at flush time would be worse than null rather
  /// than better. The queue drains when the connection returns, which can be a
  /// different person's shift; an order confidently filed under the wrong
  /// member of staff is not a record, it is a false one. The moment that
  /// answers "who rang this up" is the moment it was rung up, which is here.
  ///
  /// Null for orders queued by a build older than this field, and for a till
  /// with nobody signed in. Both are the previous behaviour — the absence of
  /// an answer, not a wrong one.
  final String? createdBy;

  Map<String, dynamic> toJson() => {
        'id': id,
        'storeId': storeId,
        'queuedAt': queuedAt.toIso8601String(),
        'createdBy': createdBy,
        'placedAt': draft.placedAt.toIso8601String(),
        'channel': draft.channel.id,
        'guestCount': draft.guestCount,
        'deliveryPlatformId': draft.deliveryPlatformId,
        'paymentMethodId': draft.paymentMethodId,
        'discountAmount': draft.discountAmount,
        'discountReason': draft.discountReason,
        'items': draft.items.map((i) => i.toMap()).toList(),
      };

  /// Returns null rather than throwing on anything it cannot read.
  ///
  /// This is parsing a file written by an older build of the app, on a device
  /// that may have been through an upgrade — the one place where "throw and
  /// let the caller deal with it" would mean a till that cannot start.
  static PendingOrder? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final storeId = json['storeId'] as String?;
    final placedAt = DateTime.tryParse(json['placedAt'] as String? ?? '');
    if (id == null || storeId == null || placedAt == null) return null;

    final items = ((json['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((i) => OrderLine.fromMap(i.cast<String, dynamic>()))
        .toList();
    if (items.isEmpty) return null;

    return PendingOrder(
      id: id,
      storeId: storeId,
      queuedAt:
          DateTime.tryParse(json['queuedAt'] as String? ?? '') ?? placedAt,
      createdBy: json['createdBy'] as String?,
      draft: OrderDraft(
        placedAt: placedAt,
        items: items,
        channel: OrderChannel.fromId(json['channel'] as String?),
        guestCount: (json['guestCount'] as num?)?.toInt() ?? 1,
        deliveryPlatformId: json['deliveryPlatformId'] as String?,
        paymentMethodId:
            json['paymentMethodId'] as String? ?? kDefaultPaymentMethodId,
        discountAmount: (json['discountAmount'] as num?)?.toInt() ?? 0,
        discountReason: json['discountReason'] as String?,
      ),
    );
  }

  static String encode(List<PendingOrder> orders) =>
      jsonEncode(orders.map((o) => o.toJson()).toList());

  static List<PendingOrder> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((json) => PendingOrder.fromJson(json.cast<String, dynamic>()))
          .whereType<PendingOrder>()
          .toList();
    } catch (_) {
      // A corrupt file loses the queue, which is bad, but a till that will not
      // open is worse.
      return const [];
    }
  }
}
