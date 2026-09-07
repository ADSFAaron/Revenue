import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/models/app_user.dart';
import 'package:Revenue/models/audit_log.dart';
import 'package:Revenue/models/order.dart';

import 'shop.dart';

/// Who may change an order, and for how long.
///
/// There are two halves to this rule and they have to agree. The server half
/// is in `firestore.rules` and is what actually stops a write — it is tested
/// against a real Firestore in `test/rules/orders.test.js`, because a rule the
/// client alone applies is not a rule. This is the client half: whether the
/// buttons are there. A client that offers an edit the server will refuse is
/// not a security hole, but it is a shop worker tapping Save and being told no
/// by an error code, which is its own kind of broken.
///
/// The two figures must stay equal to [kStaffCorrectionWindow]. That constant
/// is quoted in the user manual too, and `test/settings/user_manual_test.dart`
/// reads it from here rather than repeating it, so a change to the window
/// moves the manual, the rules test and this in one go.
void main() {
  group('a fresh order', () {
    test('staff may correct it', () {
      final order = _placed(secondsAgo: 30);

      expect(mayChangeOrder(order, UserRole.staff), isTrue);
    });

    test('and so may an owner', () {
      final order = _placed(secondsAgo: 30);

      expect(mayChangeOrder(order, UserRole.owner), isTrue);
    });
  });

  group('an order past the window', () {
    final old = _placed(minutesAgo: kStaffCorrectionWindow.inMinutes + 1);

    test('staff may not correct it', () {
      expect(mayChangeOrder(old, UserRole.staff), isFalse);
    });

    test('an owner still may — this is the void-at-end-of-shift path', () {
      expect(mayChangeOrder(old, UserRole.owner), isTrue);
    });

    test('and so may a manager', () {
      expect(mayChangeOrder(old, UserRole.manager), isTrue);
    });

    test('the boundary belongs to the past, not to the window', () {
      // Exactly five minutes is outside. The rules file compares the same way
      // — `request.time < createdAt + duration.value(5, 'm')` — and an
      // off-by-one here would offer an edit the server then refuses.
      //
      // The clock is passed in rather than left to `DateTime.now()`. Read from
      // the clock twice and the second read is microseconds later, so "exactly
      // five minutes ago" is really five minutes and a few microseconds and
      // the comparison never lands on the boundary at all — which means `<`
      // and `<=` behave identically and the test cannot tell them apart. It
      // was written that way, and a mutation run is what said so.
      final now = DateTime(2026, 9, 7, 12, 0);
      final onTheLine = _order(createdAt: now.subtract(kStaffCorrectionWindow));

      expect(mayChangeOrder(onTheLine, UserRole.staff, now: now), isFalse);
      expect(
        mayChangeOrder(
          onTheLine,
          UserRole.staff,
          now: now.subtract(const Duration(seconds: 1)),
        ),
        isTrue,
        reason: 'a second earlier is still inside the window',
      );
    });
  });

  group('the two halves of the rule', () {
    test('the client and the server are talking about the same five minutes',
        () {
      // The one test here that reads a number rather than a constant, and it
      // has to. Everything else in this file asks `kStaffCorrectionWindow`
      // what the window is, so moving that constant moves the tests with it
      // and nothing fails — which is exactly what happened when this suite was
      // put through a mutation run: the window was changed to fifty minutes
      // and the whole suite still passed.
      //
      // What that change would really do is desynchronise the two halves of
      // the rule. `firestore.rules` is what refuses the write and it carries
      // its own literal; the constant only decides whether the buttons are
      // there. Move one and a shop worker gets a live Edit button and an error
      // code when they press Save.
      //
      // Both files say "change both" in their comments. This is the thing that
      // makes that instruction enforceable.
      final rules = File('firestore.rules').readAsStringSync();
      final match = RegExp(
        r'request\.time\s*<\s*resource\.data\.createdAt\s*\+\s*'
        r"duration\.value\((\d+),\s*'m'\)",
      ).firstMatch(rules);

      expect(match, isNotNull,
          reason: 'the correction window has moved or been rewritten in '
              'firestore.rules — check this test still points at it');
      expect(
        int.parse(match!.group(1)!),
        kStaffCorrectionWindow.inMinutes,
        reason: 'firestore.rules and kStaffCorrectionWindow disagree about '
            'how long staff have to correct an order',
      );
    });
  });

  test('an order that has not reached the server is nobody\'s to correct', () {
    // `createdAt` is a server timestamp, so it is null only for an order still
    // in flight — and an order the server has not got cannot be edited on it.
    final inFlight = _order(createdAt: null);

    expect(mayChangeOrder(inFlight, UserRole.staff), isFalse);
  });

  group('viewing is never gated', () {
    test('an order older than the window is still in the history', () async {
      // The window is about changing, not about looking. Hiding a shop's own
      // records from the people who work there would be worse than useless.
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      await shop.ringUp(
        [(dish, 1)],
        at: DateTime.now().subtract(const Duration(hours: 3)),
      );

      final history = await shop.history();

      expect(history, hasLength(1));
      expect(history.single.total, 30);
      expect(await shop.orders.fetch(shop.store.id, history.single.id),
          isNotNull);
    });

    test('staff see the same history an owner does', () async {
      final shop = await Shop.opened();
      final dish = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(dish, 1)]);

      final invite = await shop.staffInvite();
      await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Cook',
      );

      // Same read, now made while the cook holds the till. What differs
      // between the two is which buttons `mayChangeOrder` puts on the screen,
      // never what is on it.
      expect(await shop.history(), hasLength(1));
    });
  });

  group('an edit that is allowed through', () {
    test('replaces the order and leaves the day\'s takings correct', () async {
      // The failure this is really about: an edit that adds the new total
      // without backing the old one out, so a corrected order is counted twice
      // and the day reads high for the rest of its life.
      final shop = await Shop.opened();
      final tea = await shop.addDish('Tea', price: 30);
      final noodles = await shop.addDish('Noodles', price: 130);
      await shop.ringUp([(tea, 1)]);

      expect((await shop.dayStats()).revenue, 30);

      final order = (await shop.history()).single;
      await shop.edit(order, [(noodles, 1)]);

      expect((await shop.history()).single.total, 130);
      expect((await shop.dayStats()).revenue, 130);
      expect((await shop.dayStats()).orderCount, 1);
    });

    test('keeps its order number', () async {
      final shop = await Shop.opened();
      final tea = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(tea, 1)]);
      await shop.ringUp([(tea, 1)]);

      final second = (await shop.history()).first;
      expect(second.orderNo, 2);

      await shop.edit(second, [(tea, 5)]);

      expect((await shop.history()).first.orderNo, 2);
    });

    test('and says who changed it', () async {
      final shop = await Shop.opened();
      final tea = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(tea, 1)]);

      final order = (await shop.history()).single;
      await shop.edit(order, [(tea, 3)],
          by: Actor(uid: shop.owner.uid, name: 'Owner'));

      final entry = (await shop.auditLog())
          .singleWhere((e) => e.action == AuditAction.editOrder);
      expect(entry.targetId, order.id);
      expect(entry.byName, 'Owner');
    });

    test('an edit never changes who rang it up', () async {
      // Mirrored in the rules — an edit may change what was sold, never the
      // attribution. Otherwise a correction is a way to move a sale onto
      // somebody else's name.
      final shop = await Shop.opened();
      final tea = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(tea, 1)], by: 'uid-cook');

      final order = (await shop.history()).single;
      await shop.edit(order, [(tea, 2)]);

      expect((await shop.history()).single.createdBy, 'uid-cook');
    });
  });

  group('voiding', () {
    test('backs the money out but keeps the order', () async {
      // Never deleted. A cancelled sale that leaves no trace is exactly the
      // gap that makes a till discrepancy unarguable.
      final shop = await Shop.opened();
      final tea = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(tea, 4)]);

      final order = (await shop.history()).single;
      await shop.orders.voidOrder(
        store: shop.store,
        orderId: order.id,
        by: Actor(uid: shop.owner.uid, name: 'Owner'),
      );

      final after = (await shop.history()).single;
      expect(after.status, OrderStatus.voided);
      expect((await shop.dayStats()).revenue, 0);
      expect((await shop.dayStats()).voidedCount, 1);
    });

    test('a voided order cannot then be edited', () async {
      final shop = await Shop.opened();
      final tea = await shop.addDish('Tea', price: 30);
      await shop.ringUp([(tea, 1)]);

      final order = (await shop.history()).single;
      await shop.orders.voidOrder(
        store: shop.store,
        orderId: order.id,
        by: Actor(uid: shop.owner.uid),
      );

      await expectLater(
        shop.edit(order, [(tea, 9)]),
        throwsA(isA<StateError>()),
      );
    });
  });
}

/// An order that reached the server at a given moment.
///
/// Built by hand rather than rung up, because `createdAt` is a server
/// timestamp and there is no way to ask a Firestore — fake or real — to
/// backdate one.
Order _placed({int secondsAgo = 0, int minutesAgo = 0}) => _order(
      createdAt: DateTime.now().subtract(
        Duration(seconds: secondsAgo, minutes: minutesAgo),
      ),
    );

Order _order({required DateTime? createdAt}) {
  final placedAt = createdAt ?? DateTime.now();
  return Order(
    id: 'o1',
    orderNo: 1,
    businessDate: '2026-09-06',
    placedAt: placedAt,
    hourOfDay: placedAt.hour,
    weekday: placedAt.weekday,
    createdAt: createdAt,
  );
}
