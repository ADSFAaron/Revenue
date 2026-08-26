import 'dart:math';

import 'package:Revenue/models/app_user.dart';
import 'package:Revenue/models/invite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the code alphabet', () {
    test('excludes every character that gets confused when read aloud', () {
      for (final confusable in ['0', 'O', '1', 'I', 'L']) {
        expect(Invite.alphabet.contains(confusable), isFalse,
            reason: '$confusable should not be in the alphabet');
      }
    });

    test('is 31 upper-case alphanumerics', () {
      expect(Invite.alphabet.length, 31);
      expect(Invite.alphabet, matches(RegExp(r'^[A-Z2-9]+$')));
      expect(Invite.alphabet.split('').toSet().length, 31,
          reason: 'no character should appear twice');
    });
  });

  group('generateCode', () {
    test('is six characters drawn from the alphabet', () {
      for (var i = 0; i < 200; i++) {
        final code = Invite.generateCode();
        expect(code.length, Invite.codeLength);
        for (final char in code.split('')) {
          expect(Invite.alphabet.contains(char), isTrue);
        }
      }
    });

    test('reaches every symbol in the alphabet', () {
      // Guards against an off-by-one in the range passed to nextInt, which
      // would silently make the last symbol unreachable and shrink the
      // keyspace without failing anything else.
      final seen = <String>{};
      final rng = Random(1);
      for (var i = 0; i < 5000; i++) {
        seen.addAll(Invite.generateCode(rng).split(''));
      }
      expect(seen.length, Invite.alphabet.length);
    });
  });

  group('normalise', () {
    test('upper-cases what was typed', () {
      expect(Invite.normalise('abcd23'), 'ABCD23');
    });

    test('drops spaces, hyphens and punctuation', () {
      expect(Invite.normalise('ABC-234'), 'ABC234');
      expect(Invite.normalise(' abc 234 '), 'ABC234');
      expect(Invite.normalise('A.B/C:2*3#4'), 'ABC234');
    });

    test('drops the excluded lookalikes rather than guessing at them', () {
      // Mapping 0→O would turn two different typos into one code, and the
      // alphabet is chosen so no such guess is ever needed.
      expect(Invite.normalise('A0BC23'), 'ABC23');
      expect(Invite.normalise('AIBC23'), 'ABC23');
    });

    test('is idempotent', () {
      final once = Invite.normalise('ab-c 234');
      expect(Invite.normalise(once), once);
    });
  });

  group('isWellFormed', () {
    test('accepts a code with separators in it', () {
      expect(Invite.isWellFormed('abc 234'), isTrue);
      expect(Invite.isWellFormed('ABC-234'), isTrue);
    });

    test('rejects anything that is not six usable characters', () {
      expect(Invite.isWellFormed(''), isFalse);
      expect(Invite.isWellFormed('ABC23'), isFalse);
      expect(Invite.isWellFormed('ABC2345'), isFalse);
      // Five usable characters plus an excluded one is still five.
      expect(Invite.isWellFormed('ABC23O'), isFalse);
    });
  });

  group('redeemability', () {
    Invite make({String? usedBy, required Duration expiresIn}) => Invite(
          code: 'ABC234',
          storeId: 's1',
          storeName: 'Noodle Shop',
          role: UserRole.staff,
          createdBy: 'uid',
          expiresAt: DateTime(2026, 8, 26, 12).add(expiresIn),
          usedBy: usedBy,
        );

    final now = DateTime(2026, 8, 26, 12);

    test('a fresh unused code is redeemable', () {
      final invite = make(expiresIn: const Duration(minutes: 30));
      expect(invite.isUsed, isFalse);
      expect(invite.isExpiredAt(now), isFalse);
      expect(invite.remainingAt(now), const Duration(minutes: 30));
    });

    test('a spent code is not redeemable however much time is left', () {
      expect(make(usedBy: 'uid2', expiresIn: const Duration(minutes: 30)).isUsed,
          isTrue);
    });

    test('expiry is exclusive — the instant it expires, it has', () {
      expect(make(expiresIn: Duration.zero).isExpiredAt(now), isTrue);
    });

    test('time remaining never goes negative', () {
      expect(make(expiresIn: const Duration(minutes: -5)).remainingAt(now),
          Duration.zero);
    });
  });

  test('display splits the code into two groups of three', () {
    expect(
      Invite(
        code: 'ABC234',
        storeId: 's1',
        storeName: 'Noodle Shop',
        role: UserRole.staff,
        createdBy: 'uid',
        expiresAt: DateTime(2026),
      ).display,
      'ABC 234',
    );
  });
}
