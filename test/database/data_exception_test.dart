import 'package:Revenue/database/repositories.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a person is shown when a read or a write fails.
///
/// The rule these tests hold is narrow and worth stating: whatever reaches
/// [describeFailure], what comes back is a sentence. Not an error code, not a
/// stack trace, not `null`, and never the empty string — because the one
/// caller of all this is a snack bar, and a snack bar with nothing in it is
/// indistinguishable from the write having worked.
void main() {
  FirebaseException firestore(String code, {String? message}) =>
      FirebaseException(plugin: 'cloud_firestore', code: code, message: message);

  group('translating Firestore failures', () {
    test('a refused write is named as permission, not as an outage', () {
      final result = describeFailure(firestore('permission-denied'));
      expect(result.failure, DataFailure.denied);
      expect(result.message, contains('permission'));
    });

    test('an unreachable database is named as the network', () {
      final result = describeFailure(firestore('unavailable'));
      expect(result.failure, DataFailure.offline);
      expect(result.message.toLowerCase(), contains('network'));
    });

    test('a lost document says so rather than blaming the person', () {
      expect(describeFailure(firestore('not-found')).failure,
          DataFailure.notFound);
    });

    test('losing a race for the same document asks for a retry', () {
      final result = describeFailure(firestore('aborted'));
      expect(result.failure, DataFailure.contention);
      expect(result.message, contains('again'));
    });

    test('a spent quota is not reported as a bug', () {
      expect(describeFailure(firestore('resource-exhausted')).failure,
          DataFailure.quota);
    });

    test('running out of time is its own failure, not an outage', () {
      expect(describeFailure(firestore('deadline-exceeded')).failure,
          DataFailure.timeout);
    });

    /// A missing composite index arrives as `failed-precondition`, and the
    /// server's own message carries the console link that creates it. Replacing
    /// that with friendlier words would throw away the only thing that fixes
    /// it — so the default branch keeps the server's message verbatim.
    test('a missing index keeps the message that carries its console link', () {
      final result = describeFailure(firestore(
        'failed-precondition',
        message: 'The query requires an index. Create it here: '
            'https://console.firebase.google.com/…',
      ));
      expect(result.message, contains('console.firebase.google.com'));
    });

    test('an unrecognised code still names itself', () {
      final result = describeFailure(firestore('something-new'));
      expect(result.message, contains('something-new'));
    });
  });

  group('failures a repository already explained', () {
    test('a SessionException keeps its own wording', () {
      const original = SessionException('This account is not linked to a '
          'store.');
      final result = describeFailure(original);
      expect(result.failure, DataFailure.alreadyExplained);
      expect(result.message, original.message);
    });

    test('a MenuImportException keeps its own wording', () {
      const original = MenuImportException('Sign in before importing a menu.');
      expect(describeFailure(original).message, original.message);
    });

    test('a DataException passes through untouched', () {
      const original = DataException(DataFailure.denied, 'No.');
      expect(identical(describeFailure(original), original), isTrue);
    });
  });

  group('anything else', () {
    /// `catch (e)` catches `Error` as well as `Exception`, so a document that
    /// does not hold what a model expects arrives here exactly like a network
    /// failure does. Both have to end as a sentence rather than as a screen
    /// that never stops spinning.
    test('a TypeError becomes a sentence, not a stack trace', () {
      final result = describeFailure(TypeError());
      expect(result.failure, DataFailure.unknown);
      expect(result.message, isNot(contains('TypeError')));
      expect(result.message, endsWith('.'));
    });

    test('a bare string is not echoed back at the person', () {
      expect(describeFailure('boom').message, isNot(contains('boom')));
    });

    test('every failure produces something worth showing', () {
      final errors = <Object>[
        firestore('permission-denied'),
        firestore('unavailable'),
        firestore('not-found'),
        firestore('aborted'),
        firestore('resource-exhausted'),
        firestore('deadline-exceeded'),
        firestore('failed-precondition'),
        firestore('whatever'),
        const SessionException('no store'),
        StateError('bad'),
        TypeError(),
        'a string',
      ];
      for (final error in errors) {
        final message = describeFailure(error).message;
        expect(message, isNotEmpty, reason: '$error produced nothing');
        expect(message, isNot(contains('cloud_firestore/')),
            reason: '$error leaked a plugin error code');
      }
    });
  });
}
