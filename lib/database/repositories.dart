import '../models/app_user.dart';
import '../models/store.dart';
import 'feedback_repository.dart';
import 'menu_repository.dart';
import 'order_repository.dart';
import 'stats_repository.dart';
import 'store_repository.dart';
import 'user_repository.dart';

export 'feedback_repository.dart';
export 'menu_repository.dart';
export 'order_repository.dart';
export 'stats_repository.dart';
export 'store_repository.dart';
export 'user_repository.dart';

/// The single entry point to stored data.
///
/// No widget may reach for `FirebaseFirestore.instance` directly. Keeping every
/// query behind these five objects is what makes the backend replaceable later
/// without touching a single screen.
final userRepository = UserRepository();
final storeRepository = StoreRepository();
final menuRepository = MenuRepository();
final orderRepository = OrderRepository();
final statsRepository = StatsRepository();
final feedbackRepository = FeedbackRepository();

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
  final uid = userRepository.currentUid;
  if (uid == null) {
    throw const SessionException('You are not signed in.');
  }

  final user = await userRepository.fetch(uid);
  if (user == null) {
    throw SessionException(
      'Signed in as ${userRepository.currentEmail ?? uid}, but this account '
      'has no profile document yet.\n\n'
      'This happens when a sign-in account outlives its Firestore data — for '
      'example after the database was cleared. Sign out and register again '
      'with the same store ID.',
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
  return Session(user: user, store: store);
}
