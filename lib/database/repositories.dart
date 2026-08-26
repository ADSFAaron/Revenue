import '../models/app_user.dart';
import '../models/audit_log.dart';
import '../models/store.dart';
import 'audit_log_repository.dart';
import 'auth_repository.dart';
import 'feedback_repository.dart';
import 'invite_repository.dart';
import 'menu_repository.dart';
import 'order_repository.dart';
import 'passkey_repository.dart';
import 'stats_repository.dart';
import 'store_repository.dart';
import 'user_repository.dart';

export 'audit_log_repository.dart';
export 'auth_repository.dart';
export 'feedback_repository.dart';
export 'invite_repository.dart';
export 'menu_repository.dart';
export 'order_repository.dart';
export 'passkey_repository.dart';
export 'stats_repository.dart';
export 'store_repository.dart';
export 'user_repository.dart';

/// The single entry point to stored data.
///
/// No widget may reach for `FirebaseFirestore.instance` or `FirebaseAuth`
/// directly. Keeping every query and every sign-in call behind these objects is
/// what makes the backend replaceable later without touching a single screen.
final authRepository = AuthRepository();
final userRepository = UserRepository(auth: authRepository);
final storeRepository = StoreRepository();
final menuRepository = MenuRepository();
final orderRepository = OrderRepository();
final passkeyRepository = PasskeyRepository(auth: authRepository);
final statsRepository = StatsRepository();
final inviteRepository = InviteRepository();
final feedbackRepository = FeedbackRepository();
final auditLogRepository = AuditLogRepository();

Actor? _lastKnownActor;

/// The signed-in person, for stamping onto audit entries.
///
/// Served from whatever [loadSession] last resolved rather than re-read: every
/// screen calls loadSession on the way in, so the name is already in hand, and
/// spending a document read per voided order to fetch a name we just had would
/// be careless. Falls back to the uid alone if a change somehow happens before
/// any session resolved — an entry naming only a uid is still far better than
/// no entry.
Actor currentActor() =>
    _lastKnownActor ?? Actor(uid: authRepository.currentUid);

/// The signed-in user together with the store they belong to.
class Session {
  const Session({required this.user, required this.store});

  final AppUser user;
  final Store store;

  String get storeId => store.id;
}

/// Raised when the signed-in account has no usable profile or store.
class SessionException implements Exception {
  const SessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Resolves "who am I → which store → the store's settings" in one call.
///
/// Four screens used to repeat this lookup inline, each with its own error
/// handling and its own idea of where the store id lived.
Future<Session> loadSession() async {
  // Signed-out and signed-in-but-unprovisioned are different failures and must
  // not report the same thing: telling someone who just signed in that they are
  // "not signed in" sends them straight back to a login screen that will not
  // help.
  final uid = authRepository.currentUid;
  if (uid == null) {
    throw const SessionException('You are not signed in.');
  }

  final user = await userRepository.fetch(uid);
  if (user == null) {
    throw SessionException(
      'Signed in as ${authRepository.currentEmail ?? uid}, but this account '
      'has no profile document yet.\n\n'
      'This happens when a sign-in account outlives its Firestore data — for '
      'example after the database was cleared. Sign out and register again, '
      'either opening a store or joining one with an invite code.',
    );
  }
  if (user.storeId.isEmpty) {
    throw const SessionException('This account is not linked to a store.');
  }

  final store = await storeRepository.fetch(user.storeId);
  if (store == null) {
    throw SessionException(
      'Your profile points at store "${user.storeId}", but no such store '
      'exists. It was probably removed after this account was created.',
    );
  }
  _lastKnownActor = Actor(uid: user.uid, name: user.displayName);
  return Session(user: user, store: store);
}
