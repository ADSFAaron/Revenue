import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/invite.dart';

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

class InviteException implements Exception {
  const InviteException(this.failure, this.message);

  final InviteFailure failure;
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
  InviteRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

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
  /// Called before the person has an account, which is why the rules allow an
  /// unauthenticated `get` here — see the comment on `invites` in
  /// firestore.rules. Nothing is written; this only exists so a mistyped code
  /// is caught on the first screen instead of after a whole form is filled in.
  Future<Invite> validate(String code) async {
    final normalised = Invite.normalise(code);
    if (normalised.length != Invite.codeLength) {
      throw const InviteException(
        InviteFailure.notFound,
        'An invite code is 6 characters.',
      );
    }

    final DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await _invites.doc(normalised).get();
    } on FirebaseException catch (e) {
      throw _translate(e);
    }
    return _requireRedeemable(doc);
  }

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
  Stream<List<Invite>> watchForStore(String storeId, {int limit = 20}) =>
      _invites
          .where('storeId', isEqualTo: storeId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(Invite.fromDoc).toList());

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
                'owner can issue invite codes.',
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
