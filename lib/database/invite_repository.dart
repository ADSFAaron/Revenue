import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'session_apps.dart';

import '../models/app_user.dart';
import '../models/invite.dart';
import 'data_exception.dart';
import 'passkey_repository.dart' show passkeyFunctionsRegion;

/// Why an invite code could not be used.
///
/// Screens branch on this: "that code has already been used" and "no such
/// code" send a person to two different places, and neither is served by a
/// single generic message.
enum InviteFailure {
  /// No document with that id. Almost always a typo.
  notFound,

  /// Somebody already redeemed it. Codes are single-use.
  alreadyUsed,

  expired,

  /// The rules rejected the write — the caller is not a manager of the store,
  /// or lost a race for the same code.
  denied,

  unknown,
}

class InviteException implements AppException {
  const InviteException(this.failure, this.message);

  final InviteFailure failure;

  @override
  final String message;

  @override
  String toString() => message;
}

/// Everything that touches `invites/{code}`.
///
/// A top-level collection rather than a subcollection of the store, because a
/// code is validated by somebody who does not belong to any store yet and so
/// cannot be given a path under one.
class InviteRepository {
  InviteRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _injected = firestore,
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: passkeyFunctionsRegion);

  final FirebaseFirestore? _injected;

  /// Read through the session that is current, not captured once.
  ///
  /// A counter tablet can hold several operators signed in at the same time,
  /// one Firebase app each, and handing the till over swaps which of them is
  /// current. A handle captured in the constructor would keep answering as the
  /// person who was at the till when this object was built. See SessionApps.
  FirebaseFirestore get _db =>
      _injected ?? FirebaseFirestore.instanceFor(app: sessionApps.active);

  /// Only [validate] uses this. Everything else here is a real Firestore
  /// transaction and stays one — see the class comment.
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _invites =>
      _db.collection('invites');

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  /// How many fresh codes to try before giving up on a collision. With 887
  /// million codes and a handful live at a time, reaching two is already
  /// vanishingly unlikely; five is there so a bug cannot spin forever.
  static const int _maxCodeAttempts = 5;

  /// Issues a code for [storeId]. Manager-only, enforced by the rules.
  ///
  /// The write goes through a transaction that first reads the candidate id,
  /// so a code that happens to collide with a live one is retried rather than
  /// overwriting it. (The rules would reject the overwrite anyway — writing
  /// over an existing document is an `update`, and the update rule only allows
  /// redemption — but failing with "that code is taken" and no retry would be
  /// a needlessly poor outcome for a one-in-a-million event.)
  Future<Invite> create({
    required String storeId,
    required String storeName,
    required UserRole role,
    required String createdBy,
    Duration ttl = Invite.defaultTtl,
  }) async {
    if (role == UserRole.owner) {
      throw ArgumentError.value(
        role,
        'role',
        'A store has one owner, and it is whoever opened it.',
      );
    }

    for (var attempt = 0; attempt < _maxCodeAttempts; attempt++) {
      final invite = Invite(
        code: Invite.generateCode(),
        storeId: storeId,
        storeName: storeName,
        role: role,
        createdBy: createdBy,
        expiresAt: DateTime.now().add(ttl),
      );

      try {
        // A null return means the id was taken. Signalled by the return value
        // rather than by throwing, so this does not depend on how the plugin
        // propagates an exception raised inside the transaction handler.
        final written = await _db.runTransaction<Invite?>((tx) async {
          final ref = _invites.doc(invite.code);
          final existing = await tx.get(ref);
          if (existing.exists) return null;
          tx.set(ref, {
            ...invite.toMap(),
            'createdAt': FieldValue.serverTimestamp(),
          });
          return invite;
        });
        if (written != null) return written;
      } on FirebaseException catch (e) {
        throw _translate(e);
      }
    }

    throw const InviteException(
      InviteFailure.unknown,
      'Could not find an unused code. Please try again.',
    );
  }

  /// Looks a code up and checks it can still be used.
  ///
  /// Called before the person has an account, which is the whole difficulty:
  /// there is no signed-in caller to check a security rule against. This used
  /// to be a direct `get()` on `invites/{code}`, served by
  /// `allow get: if true` — the one unauthenticated read in the whole project.
  ///
  /// It now asks the `checkInvite` callable instead. Two things change.
  /// App Check gates it, so a code can only be tested from a real build of
  /// this app rather than from anything that can reach the internet; and the
  /// answer carries the store's *name* and the role, never its `storeId` —
  /// the id every security rule is keyed on, which a holder of a stray code
  /// could previously read straight out of the document.
  ///
  /// The returned [Invite] therefore has an empty `storeId` and `createdBy`.
  /// Nothing between here and [redeem] reads either: the registration screen
  /// shows `storeName` and `role`, and the redemption transaction reads the
  /// document itself, as a signed-in caller, at the moment it spends it.
  ///
  /// Nothing is written. This only exists so a mistyped code is caught on the
  /// first screen instead of after a whole form is filled in.
  Future<Invite> validate(String code) async {
    final normalised = Invite.normalise(code);
    if (normalised.length != Invite.codeLength) {
      throw const InviteException(
        InviteFailure.notFound,
        'An invite code is 6 characters.',
      );
    }

    // `dynamic` rather than the type argument passed to `call` below: what
    // comes back is re-checked a few lines down before any field is read, and
    // an annotation claiming otherwise would make that look redundant.
    final HttpsCallableResult<dynamic> result;
    try {
      result = await _functions
          .httpsCallable('checkInvite')
          .call<Map<String, dynamic>>({'code': normalised});
    } on FirebaseFunctionsException catch (e) {
      throw _translateCallable(e);
    } on FirebaseException catch (e) {
      throw _translate(e);
    }

    final data = Map<String, dynamic>.from(result.data as Map);
    return Invite(
      code: data['code'] as String? ?? normalised,
      // Deliberately absent. See the note above: the server does not send it,
      // and nothing before [redeem] wants it.
      storeId: '',
      storeName: data['storeName'] as String? ?? '',
      role: UserRole.fromId(data['role'] as String?),
      createdBy: '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (data['expiresAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// The callable's refusals, back into the same four cases the screens
  /// already branch on.
  ///
  /// `checkInvite` picks its error codes so this mapping is exact rather than
  /// a guess at a message: `not-found`, `already-exists` and
  /// `deadline-exceeded` are the three ways a code can be unusable, and they
  /// send a person to three different places.
  InviteException _translateCallable(FirebaseFunctionsException e) =>
      switch (e.code) {
        'not-found' => InviteException(
            InviteFailure.notFound,
            e.message ??
                'No invite with that code. Check it with whoever gave it to '
                    'you.',
          ),
        'already-exists' => InviteException(
            InviteFailure.alreadyUsed,
            e.message ??
                'That code has already been used. Codes work once — ask for a '
                    'new one.',
          ),
        'deadline-exceeded' => InviteException(
            InviteFailure.expired,
            e.message ?? 'That code has expired. Ask for a new one.',
          ),
        'invalid-argument' => InviteException(
            InviteFailure.notFound,
            e.message ?? 'An invite code is 6 characters.',
          ),
        // App Check refused the call. Worth saying plainly rather than as
        // "unknown error": on a debug build it means the debug token is not
        // registered, and on a web build it means APP_CHECK_RECAPTCHA_KEY was
        // not passed at build time. Neither is anything the person typing a
        // code can fix, so it does not pretend otherwise.
        'unauthenticated' => const InviteException(
            InviteFailure.denied,
            'This copy of the app could not verify itself. Please reinstall '
            'it from the Play Store, or contact whoever set it up.',
          ),
        'unavailable' => const InviteException(
            InviteFailure.unknown,
            'No connection. Check your network and try again.',
          ),
        _ => InviteException(
            InviteFailure.unknown,
            e.message ?? 'The code could not be checked (${e.code}).',
          ),
      };

  /// Marks [code] used and creates `users/{uid}` in one commit.
  ///
  /// Both writes land together or neither does, so two people racing on the
  /// same code produce exactly one member. This is an ordinary client
  /// transaction — Firestore's are real cross-document transactions, so the
  /// invite flow needs no Cloud Function and the project needs no Blaze plan.
  ///
  /// The caller must already be signed in as [uid]: the user document is
  /// written under that uid, and the rules check it against `request.auth`.
  Future<Invite> redeem({
    required String code,
    required String uid,
    required String email,
    required String displayName,
  }) async {
    final normalised = Invite.normalise(code);
    final inviteRef = _invites.doc(normalised);

    // Why the code was unusable, if it was. Carried out of the handler rather
    // than thrown through it: the handler may run more than once, and an
    // exception raised inside it is at the mercy of the plugin's error
    // plumbing. Reset on every attempt, for the same reason.
    InviteException? rejected;

    try {
      final invite = await _db.runTransaction<Invite?>((tx) async {
        rejected = null;

        // Read first — a transaction may not read after it has written.
        final snapshot = await tx.get(inviteRef);
        final Invite invite;
        try {
          invite = _requireRedeemable(snapshot);
        } on InviteException catch (e) {
          // Queue no writes and let the transaction commit as a no-op.
          rejected = e;
          return null;
        }

        tx.set(_users.doc(uid), {
          'uid': uid,
          'email': email,
          'displayName': displayName,
          'storeId': invite.storeId,
          'role': invite.role.id,
          // The rules read this back to find the invite they must check this
          // create against. Without it there is nothing tying the storeId and
          // role being claimed to anything that granted them.
          'joinedViaCode': normalised,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        tx.update(inviteRef, {
          'usedBy': uid,
          'usedAt': FieldValue.serverTimestamp(),
        });

        return invite;
      });

      if (invite != null) return invite;
      throw rejected ??
          const InviteException(
            InviteFailure.unknown,
            'The invite could not be redeemed.',
          );
    } on FirebaseException catch (e) {
      throw _translate(e);
    }
  }

  /// The codes issued for a store, newest first. Managers only.
  ///
  /// Capped rather than unbounded: this list is a working view of what is
  /// currently live, not an archive, and a store that has invited people for
  /// years should not pay to read all of it.
  ///
  /// Stream failures are translated here rather than left raw. A snapshot
  /// error arrives as a `FirebaseException` on the stream, not as a throw the
  /// call site can catch, so without this the screen had nothing to show but
  /// `[cloud_firestore/permission-denied] Missing or insufficient
  /// permissions.` — which tells a shop owner nothing and tells a developer
  /// only half of it.
  Stream<List<Invite>> watchForStore(String storeId, {int limit = 20}) =>
      _invites
          .where('storeId', isEqualTo: storeId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(Invite.fromDoc).toList())
          .handleError(
            (Object e) => throw _translate(e as FirebaseException),
            test: (e) => e is FirebaseException,
          );

  /// Withdraws a code that has not been used. A manager who reads a code out
  /// to the wrong person needs a way to take it back before it expires.
  Future<void> revoke(String code) async {
    try {
      await _invites.doc(Invite.normalise(code)).delete();
    } on FirebaseException catch (e) {
      throw _translate(e);
    }
  }

  Invite _requireRedeemable(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!doc.exists) {
      throw const InviteException(
        InviteFailure.notFound,
        'No invite with that code. Check it with whoever gave it to you.',
      );
    }
    final invite = Invite.fromDoc(doc);
    if (invite.isUsed) {
      throw const InviteException(
        InviteFailure.alreadyUsed,
        'That code has already been used. Codes work once — ask for a new one.',
      );
    }
    if (invite.isExpired) {
      throw const InviteException(
        InviteFailure.expired,
        'That code has expired. Ask for a new one.',
      );
    }
    return invite;
  }

  InviteException _translate(FirebaseException e) => switch (e.code) {
        'permission-denied' => const InviteException(
            InviteFailure.denied,
            'You do not have permission to do that. Only a manager or the '
            'owner can issue invite codes — and the store\'s security '
            'rules have to be deployed for this screen to read them.',
          ),
        // Almost always the invites composite index (storeId + createdAt) not
        // being deployed. The server's message carries the console link that
        // creates it, so it is passed through rather than reworded.
        'failed-precondition' => InviteException(
            InviteFailure.unknown,
            'The database needs an index for this list. '
            '${e.message ?? ''}',
          ),
        'unavailable' => const InviteException(
            InviteFailure.unknown,
            'No connection to the database. Check your network.',
          ),
        _ => InviteException(
            InviteFailure.unknown,
            e.message ?? 'The invite could not be processed (${e.code}).',
          ),
      };
}
