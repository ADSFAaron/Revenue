import 'package:firebase_core/firebase_core.dart';

/// Anything this app throws at a screen on purpose.
///
/// Every repository already translates its own backend's vocabulary into a
/// sentence worth showing — [AuthException], [InviteException],
/// [MenuImportException], [PasskeyException], [SessionException]. What they
/// lacked was a common type, so a screen catching one of them had no way to
/// tell "a message written for this person" apart from a raw
/// `FirebaseException` whose `toString()` is
/// `[cloud_firestore/permission-denied] Missing or insufficient permissions.`
///
/// That is what this interface is for, and [describeFailure] is what reads it.
abstract class AppException implements Exception {
  /// Plain words, already free of error codes and stack traces.
  String get message;
}

/// Why a read or a write did not happen.
///
/// Screens overwhelmingly only want [DataException.message]. The enum is here
/// for the few decisions that turn on *which* failure it was — a retry button
/// makes sense for [offline] and is a lie for [denied].
enum DataFailure {
  /// A repository translated this one itself; the message is its wording.
  alreadyExplained,

  /// The security rules refused it, or nobody is signed in.
  denied,

  /// No route to Firestore. The write is not lost — Firestore keeps it queued
  /// — but nothing can be confirmed.
  offline,

  /// The document is gone. Usually something was deleted on another device
  /// between the read and the write.
  notFound,

  /// Too many writers for the same document at once, and the transaction gave
  /// up. The only sensible response is to try again.
  contention,

  /// The project's Firestore quota is spent, or a rate limit was hit.
  quota,

  /// The call was still running when it ran out of time.
  timeout,

  unknown,
}

/// A storage failure, already translated out of Firebase's vocabulary.
class DataException implements AppException {
  const DataException(this.failure, this.message);

  final DataFailure failure;

  @override
  final String message;

  @override
  String toString() => message;
}

/// Turns anything caught around a read or a write into something showable.
///
/// Takes `Object` rather than `Exception` because `catch (e)` in Dart catches
/// `Error` too, and the boundary this sits on is the one place that must not
/// itself throw. A `TypeError` from a document that does not hold what the
/// model expects arrives here exactly like a network failure does, and both
/// have to end as a sentence rather than as a screen that never stops
/// spinning.
///
/// An [AppException] passes straight through: its message was written for this
/// situation and nothing here can improve on it.
DataException describeFailure(Object error) {
  if (error is DataException) return error;
  if (error is AppException) {
    return DataException(DataFailure.alreadyExplained, error.message);
  }
  if (error is FirebaseException) return _fromFirebase(error);
  return const DataException(
    DataFailure.unknown,
    'Something went wrong. Please try again.',
  );
}

/// Firestore's status codes are gRPC's, so this mapping is the same one that
/// applies to the callables in functions/.
DataException _fromFirebase(FirebaseException e) => switch (e.code) {
      'permission-denied' || 'unauthenticated' => const DataException(
          DataFailure.denied,
          'You do not have permission to do that. Ask the store owner if you '
              'should.',
        ),
      'unavailable' => const DataException(
          DataFailure.offline,
          'No connection to the database. Check your network and try again.',
        ),
      'not-found' => const DataException(
          DataFailure.notFound,
          'That record no longer exists. It may have been removed on another '
              'device.',
        ),
      'aborted' => const DataException(
          DataFailure.contention,
          'Somebody else was saving at the same moment. Please try again.',
        ),
      'resource-exhausted' => const DataException(
          DataFailure.quota,
          'The database is over its limit for now. Try again in a few '
              'minutes.',
        ),
      'deadline-exceeded' => const DataException(
          DataFailure.timeout,
          'That took too long to finish. Check your network and try again.',
        ),
      // `failed-precondition` is nearly always a missing composite index, and
      // the server's own message carries the console link that creates it.
      // Replacing it with friendlier words would throw away the only thing
      // that fixes it.
      _ => DataException(
          DataFailure.unknown,
          e.message ?? 'The database rejected that (${e.code}).',
        ),
    };
