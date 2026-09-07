import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/database/auth_repository.dart';

import 'shop.dart';

/// Getting back in.
///
/// Nothing here has ever crashed: `signIn` throws an [AuthException] and the
/// sign-in screen catches it and puts the message under the password field.
/// What is ours to get wrong is *which* failure arrives, because two screens
/// read the enum rather than the sentence:
///
///   * `AccountFields.showAuthError` — `weakPassword` goes under the password
///     field, `emailInUse` and `invalidEmail` under the email field, and
///     anything else is handed back for the caller to put in a snackbar. A
///     failure mis-mapped to `unknown` therefore leaves registration pointing
///     at no field at all.
///   * Change Password — `wrongPassword` has to read "that is not your
///     *current* password", because the generic wording sent people off to
///     check the new one.
///
/// So the codes Firebase actually returns are what [FakeAuth] throws, and this
/// checks each comes out the other side as the thing those screens branch on.
///
/// **Google and passkeys are not here, and cannot be.** Both hand control to
/// something outside the app — Google's account chooser, the platform
/// authenticator and its biometric prompt — and neither exists in a Dart test
/// process. `AuthRepository.signInWithGoogle` also reaches Cloud Functions for
/// the passkey half. They are on the manual list in `docs/testing.md`; there is
/// no way to make that list empty, only to keep it short and honest.
void main() {
  group('email and password', () {
    test('the right password gets the right person back', () async {
      final shop = await Shop.opened(
        email: 'owner@example.com',
        password: 'correct horse',
      );
      final ownerUid = shop.owner.uid;
      await shop.authRepository.signOut();

      final back = await shop.signIn(
        email: 'owner@example.com',
        password: 'correct horse',
      );

      expect(back.uid, ownerUid);
      expect(shop.authRepository.currentUid, ownerUid);
      expect(back.storeId, shop.store.id);
    });

    test('a wrong password is a wrong password, not an unknown error',
        () async {
      // The distinction earns its keep in Change Password, which has to tell
      // somebody it was their *current* password that was refused.
      final shop = await Shop.opened(password: 'correct horse');
      await shop.authRepository.signOut();

      await expectLater(
        shop.authRepository.signIn(
          email: 'owner@example.com',
          password: 'battery staple',
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.wrongPassword,
        )),
      );
      expect(shop.authRepository.currentUid, isNull);
    });

    test('an address with no account reads the same as a wrong password',
        () async {
      // Deliberately indistinguishable. Firebase collapsed the two codes so
      // that nobody can fish for which addresses have accounts, and the app
      // must not undo that by wording them differently.
      final shop = await Shop.opened();
      await shop.authRepository.signOut();

      await expectLater(
        shop.authRepository.signIn(
          email: 'nobody@example.com',
          password: 'correct horse',
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.wrongPassword,
        )),
      );
    });

    test('signing out leaves nobody signed in', () async {
      final shop = await Shop.opened();

      await shop.authRepository.signOut();

      expect(shop.authRepository.currentUid, isNull);
      expect(shop.authRepository.currentEmail, isNull);
    });

    test('a password account is one the app may offer to change', () async {
      // `hasPasswordSignIn` is what stops the settings screen demanding a
      // current password from a Google account that has never had one.
      final shop = await Shop.opened();

      expect(shop.authRepository.hasPasswordSignIn, isTrue);
    });
  });

  group('registering', () {
    test('an address that already has an account is refused as such',
        () async {
      final shop = await Shop.opened(email: 'taken@example.com');

      await expectLater(
        shop.authRepository.register(
          email: 'taken@example.com',
          password: 'another one',
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.emailInUse,
        )),
      );
    });

    test('a short password is refused before a shop is written', () async {
      final shop = await Shop.opened();
      final storesBefore = await shop.db.collection('stores').get();

      await expectLater(
        shop.authRepository.register(email: 'new@example.com', password: 'abc'),
        throwsA(isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.weakPassword,
        )),
      );

      final storesAfter = await shop.db.collection('stores').get();
      expect(storesAfter.docs, hasLength(storesBefore.docs.length));
    });
  });

  group('the till changing hands', () {
    test('two accounts on one device stay separate', () async {
      // A counter tablet holds more than one operator. What must never happen
      // is an order being attributed to whoever was signed in last rather than
      // to whoever rang it up.
      final shop = await Shop.opened(
        email: 'owner@example.com',
        password: 'correct horse',
      );
      final invite = await shop.staffInvite();
      final cook = await shop.join(
        code: invite.code,
        email: 'cook@example.com',
        password: 'another one',
        displayName: 'Cook',
      );

      expect(shop.authRepository.currentUid, cook.uid);

      await shop.authRepository.signOut();
      final back = await shop.signIn(
        email: 'owner@example.com',
        password: 'correct horse',
      );

      expect(back.uid, shop.owner.uid);
      expect(back.uid, isNot(cook.uid));
    });
  });
}
