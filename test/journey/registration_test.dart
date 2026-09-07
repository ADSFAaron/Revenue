import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/database/invite_repository.dart';
import 'package:Revenue/models/app_user.dart';
import 'package:Revenue/models/invite.dart';

import 'shop.dart';

/// The two ways a person ends up inside a shop, and the state each leaves
/// behind.
///
/// Registration is the only flow in the app that writes across three places at
/// once — an account, a profile and a store — and the half-finished versions
/// of it are the expensive ones. An account with no profile is somebody who
/// can sign in and reach nothing; a profile pointing at a store that was never
/// written is the same thing wearing a different error. Both have shipped, and
/// `loadSession` carries wording for both, so what is pinned here is that the
/// happy path leaves none of them.
void main() {
  group('opening a new store', () {
    test('leaves an owner who can be resolved to a shop', () async {
      final shop = await Shop.opened(name: 'Corner Noodles');

      expect(shop.owner.storeId, shop.store.id);
      expect(shop.owner.role, UserRole.owner);
      expect(shop.owner.active, isTrue);
      expect(shop.store.name, 'Corner Noodles');
    });

    test('the account, the profile and the store all exist', () async {
      final shop = await Shop.opened(email: 'boss@example.com');

      expect(shop.authRepository.currentUid, shop.owner.uid);
      expect(shop.authRepository.currentEmail, 'boss@example.com');
      expect(await shop.users.fetch(shop.owner.uid), isNotNull);
      expect(await shop.stores.exists(shop.store.id), isTrue);
    });

    test('a new store starts with an empty menu', () async {
      // Registration used to seed six dishes into every new store. That menu
      // belonged to nobody and invited a sale against a dish this kitchen has
      // never sold — see the note in `MenuRepository`.
      final shop = await Shop.opened();

      expect(await shop.menu.fetchAll(shop.store.id), isEmpty);
    });

    test('and no takings at all', () async {
      final shop = await Shop.opened();

      expect((await shop.dayStats()).revenue, 0);
      expect(await shop.history(), isEmpty);
    });
  });

  group('joining a store with an invite', () {
    test('puts the new person in the same shop, at the invited role',
        () async {
      final shop = await Shop.opened();
      final invite = await shop.invites.create(
        storeId: shop.store.id,
        storeName: shop.store.name,
        role: UserRole.staff,
        createdBy: shop.owner.uid,
      );

      final joiner = await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Cook',
      );

      expect(joiner.storeId, shop.store.id);
      expect(joiner.role, UserRole.staff);
      expect(joiner.active, isTrue);
    });

    test('a manager invite makes a manager, not staff', () async {
      final shop = await Shop.opened();
      final invite = await shop.invites.create(
        storeId: shop.store.id,
        storeName: shop.store.name,
        role: UserRole.manager,
        createdBy: shop.owner.uid,
      );

      final joiner = await shop.join(
        code: invite.code,
        email: 'manager@example.com',
        password: 'another one',
        displayName: 'Manager',
      );

      expect(joiner.role, UserRole.manager);
      expect(joiner.role.canManage, isTrue);
    });

    test('the code is spent, so a second person cannot ride it in', () async {
      final shop = await Shop.opened();
      final invite = await shop.invites.create(
        storeId: shop.store.id,
        storeName: shop.store.name,
        role: UserRole.staff,
        createdBy: shop.owner.uid,
      );

      await shop.join(
        code: invite.code,
        email: 'first@example.com',
        password: 'another one',
        displayName: 'First',
      );

      await expectLater(
        shop.join(
          code: invite.code,
          email: 'second@example.com',
          password: 'another one',
          displayName: 'Second',
        ),
        throwsA(isA<InviteException>()),
      );
    });

    test('an expired code is refused', () async {
      final shop = await Shop.opened();
      final invite = await shop.invites.create(
        storeId: shop.store.id,
        storeName: shop.store.name,
        role: UserRole.staff,
        createdBy: shop.owner.uid,
        ttl: const Duration(milliseconds: -1),
      );

      await expectLater(
        shop.join(
          code: invite.code,
          email: 'late@example.com',
          password: 'another one',
          displayName: 'Late',
        ),
        throwsA(isA<InviteException>()),
      );
    });

    test('a code nobody issued is refused', () async {
      final shop = await Shop.opened();

      await expectLater(
        shop.join(
          code: Invite.generateCode(),
          email: 'chancer@example.com',
          password: 'another one',
          displayName: 'Chancer',
        ),
        throwsA(isA<InviteException>()),
      );
    });

    test('a store has one owner, and an invite cannot mint another', () async {
      final shop = await Shop.opened();

      expect(
        () => shop.invites.create(
          storeId: shop.store.id,
          storeName: shop.store.name,
          role: UserRole.owner,
          createdBy: shop.owner.uid,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
