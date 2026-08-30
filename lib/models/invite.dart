import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';

/// `invites/{code}` — a single-use code that lets somebody join a store.
///
/// The code is the document id rather than a field: that makes it unique for
/// free, resolvable with one `get()` instead of a query, and it needs no index.
///
/// This is what replaced typing a 36-character store UUID into the
/// registration form. A manager generates a code, reads it across the kitchen,
/// and the new colleague types six characters.
class Invite {
  const Invite({
    required this.code,
    required this.storeId,
    required this.storeName,
    required this.role,
    required this.createdBy,
    required this.expiresAt,
    this.createdAt,
    this.usedBy,
    this.usedAt,
  });

  /// The six characters a person actually types. Also the document id.
  final String code;

  final String storeId;

  /// Denormalised on purpose. The code is checked *before* the person belongs
  /// to any store — at that moment they cannot read `stores/{id}`, so the name
  /// they are shown to confirm ("You are joining: …") has to live here.
  final String storeName;

  /// What the redeemer becomes. Never `owner`: a store has exactly one, and it
  /// is whoever opened it.
  final UserRole role;

  final String createdBy;
  final DateTime expiresAt;
  final DateTime? createdAt;

  /// The uid that spent this code, or null while it is still unused. Written
  /// as an explicit null rather than left absent so the security rules can
  /// compare against it without the field-missing case erroring the rule out.
  final String? usedBy;

  final DateTime? usedAt;

  /// How long a fresh code stays valid. Long enough to walk across a kitchen
  /// and short enough that a code on a scrap of paper stops working.
  static const Duration defaultTtl = Duration(minutes: 30);

  static const int codeLength = 6;

  /// The alphabet a code is drawn from: upper-case alphanumerics minus
  /// `0 O 1 I L`. This code gets read aloud over a noisy kitchen or copied
  /// onto a scrap of paper, so the characters that get confused when spoken
  /// or written by hand are simply not in it. 31 symbols over six places is
  /// about 887 million codes.
  static const String alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// A fresh code. Uses [Random.secure] — a guessable code is a way into
  /// somebody's books.
  static String generateCode([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      codeLength,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }

  /// Cleans up what a person typed: upper-cases it and drops spaces, hyphens
  /// and anything else outside the alphabet. Someone who writes `abc-123` down
  /// and types it back with the hyphen should not be told their code is wrong.
  ///
  /// Deliberately does *not* fold lookalikes (`0`→`O`, `1`→`I`): those
  /// characters are excluded from the alphabet precisely so no such guess is
  /// ever needed, and guessing here would map two distinct typos onto one code.
  static String normalise(String input) {
    final upper = input.toUpperCase();
    final buffer = StringBuffer();
    for (final char in upper.split('')) {
      if (alphabet.contains(char)) buffer.write(char);
    }
    return buffer.toString();
  }

  /// Whether [input] could be a code at all, checked before spending a network
  /// round trip on it.
  static bool isWellFormed(String input) =>
      normalise(input).length == codeLength;

  factory Invite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Invite(
      code: doc.id,
      storeId: data['storeId'] as String? ?? '',
      storeName: data['storeName'] as String? ?? '',
      role: UserRole.fromId(data['role'] as String?),
      createdBy: data['createdBy'] as String? ?? '',
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ?? DateTime(1970),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      usedBy: data['usedBy'] as String?,
      usedAt: (data['usedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// `createdAt` is left to the repository so it can use the server clock.
  /// `expiresAt` cannot be: the rules compare it against `request.time` at
  /// creation, and a sentinel has no value to compare yet.
  Map<String, dynamic> toMap() => {
        'storeId': storeId,
        'storeName': storeName,
        'role': role.id,
        'createdBy': createdBy,
        'expiresAt': Timestamp.fromDate(expiresAt),
        'usedBy': usedBy,
      };

  bool get isUsed => usedBy != null;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  bool get isExpired => isExpiredAt(DateTime.now());

  /// Time left before this code stops working, floored at zero.
  Duration remainingAt(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// The code broken into two groups of three, which is how a person reads it
  /// out loud and how they are least likely to lose their place.
  String get display => code.length == codeLength
      ? '${code.substring(0, 3)} ${code.substring(3)}'
      : code;
}
