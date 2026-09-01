import 'package:flutter_test/flutter_test.dart';

import 'package:Revenue/models/order.dart';
import 'package:Revenue/models/order_draft.dart';
import 'package:Revenue/models/pending_order.dart';

/// What an order rung up offline has to survive: a shut-down, an upgrade, and
/// being sent hours after it was taken.
void main() {
  final draft = OrderDraft(
    placedAt: DateTime(2026, 8, 30, 13, 45),
    items: const [
      OrderLine(
        itemId: 'i1',
        name: '牛肉麵',
        categoryId: 'c1',
        unitPrice: 180,
        unitCost: 70,
        qty: 2,
      ),
    ],
    channel: OrderChannel.takeout,
    guestCount: 2,
    paymentMethodId: 'line_pay',
  );

  final pending = PendingOrder(
    id: 'abc123',
    storeId: 's1',
    queuedAt: DateTime(2026, 8, 30, 13, 46),
    draft: draft,
  );

  test('a queued order keeps everything the till chose', () {
    final restored = PendingOrder.decode(PendingOrder.encode([pending])).single;

    expect(restored.id, 'abc123');
    expect(restored.storeId, 's1');
    // The time it was rung up at, not the time it is sent. An order taken at
    // lunch and sent at four belongs to lunch — and across the 04:00 cutoff,
    // to the previous trading day.
    expect(restored.draft.placedAt, DateTime(2026, 8, 30, 13, 45));
    expect(restored.draft.channel, OrderChannel.takeout);
    expect(restored.draft.guestCount, 2);
    expect(restored.draft.paymentMethodId, 'line_pay');
    expect(restored.draft.items.single.name, '牛肉麵');
    // The price as it was on the menu at the time, which is the whole reason
    // OrderLine carries its own copy.
    expect(restored.draft.items.single.unitPrice, 180);
    expect(restored.draft.items.single.unitCost, 70);
    expect(restored.draft.items.single.qty, 2);
  });

  test('the id is allocated before sending, so sending twice is detectable',
      () {
    // Not a round-trip detail: the id is what makes the flush idempotent —
    // orderRepository.submit sees the document already exists and stops.
    final restored = PendingOrder.decode(PendingOrder.encode([pending])).single;
    expect(restored.id, pending.id);
  });

  test('a queue file from an older build does not stop the till', () {
    expect(PendingOrder.decode(null), isEmpty);
    expect(PendingOrder.decode(''), isEmpty);
    expect(PendingOrder.decode('not json at all'), isEmpty);
    expect(PendingOrder.decode('{"not":"a list"}'), isEmpty);
  });

  test('an unreadable entry is dropped, the readable ones are kept', () {
    final mixed = '[{"id":"x"},${PendingOrder.encode([pending]).substring(1)}';
    final restored = PendingOrder.decode(mixed);
    expect(restored.length, 1);
    expect(restored.single.id, 'abc123');
  });

  test('an order with no lines is not an order', () {
    final empty = PendingOrder(
      id: 'e',
      storeId: 's1',
      queuedAt: DateTime(2026, 8, 30),
      draft: OrderDraft(placedAt: DateTime(2026, 8, 30), items: const []),
    );
    expect(PendingOrder.decode(PendingOrder.encode([empty])), isEmpty);
  });
}
