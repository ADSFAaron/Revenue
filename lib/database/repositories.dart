import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

export 'connection_status.dart' show ConnectionStatus, connectionStatus;
export 'pending_order_queue.dart' show PendingOrderQueue;

import '../models/app_user.dart';
import '../models/audit_log.dart';
import '../models/store.dart';
import 'audit_log_repository.dart';
import 'auth_repository.dart';
import 'data_exception.dart';
import 'feedback_repository.dart';
import 'invite_repository.dart';
import 'menu_import_repository.dart';
import 'menu_repository.dart';
import 'order_repository.dart';
import 'pending_order_queue.dart';
import 'passkey_repository.dart';
import 'stats_repository.dart';
import 'store_repository.dart';
import 'user_repository.dart';

export 'audit_log_repository.dart';
export 'auth_repository.dart';
export 'data_exception.dart';
export 'feedback_repository.dart';
export 'invite_repository.dart';
export 'menu_import_repository.dart';
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
/// Turns on the offline cache. Call once, before the first read.
///
/// Set explicitly rather than left to each platform's default: the mobile SDKs
/// enable persistence, the web SDK does not. The same shop on a tablet kept
/// working through a dropped connection and on a laptop went blank. A
/// kitchen's wifi is the case this app should assume, not the one it should be
/// surprised by.
void configureFirestore() {
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
}

/// Attests that a request came from a genuine build of this app.
///
/// The rules decide what a *signed-in account* may do. Nothing until now
/// decided whether the caller was this app at all — and since anybody can
/// register in seconds with no email verification, "a valid account" is not a
/// meaningful barrier. App Check is the missing half: Play Integrity has
/// Google vouch for the installation, and a script holding a valid login gets
/// no token at all.
///
/// It matters most for the menu import, which is the one call in this project
/// that spends real money per invocation. `functions/src/quota.ts` caps how
/// much can be spent in a day; this decides who gets to spend it.
///
/// **Debug builds use the debug provider**, which mints a token for a local
/// secret rather than attesting anything. That secret has to be pasted into
/// the Firebase console once per machine (App Check → the Android app →
/// Manage debug tokens); the token is printed to the log on first run. Without
/// this branch, every `flutter run` would be refused by its own backend as
/// soon as enforcement is switched on.
///
/// **Web needs a reCAPTCHA Enterprise site key**, which is per-project and not
/// a secret, but is also not something this repository should guess. Pass it
/// at build time and web activation is skipped when it is absent:
///
/// ```
/// flutter build web --dart-define=APP_CHECK_RECAPTCHA_KEY=6Lc...
/// ```
///
/// Failure here is swallowed on purpose. App Check activation talks to the
/// network, and a till that cannot reach Google at launch must still open —
/// the enforcement decision lives on the server, where a missing token is
/// refused per request rather than at startup.
Future<void> configureAppCheck() async {
  const recaptchaKey = String.fromEnvironment('APP_CHECK_RECAPTCHA_KEY');
  if (kIsWeb && recaptchaKey.isEmpty) return;
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerWeb:
          recaptchaKey.isEmpty ? null : ReCaptchaEnterpriseProvider(recaptchaKey),
    );
  } catch (e) {
    debugPrint('App Check activation failed: $e');
  }
}

final authRepository = AuthRepository();
final userRepository = UserRepository(auth: authRepository);
final storeRepository = StoreRepository();
final menuRepository = MenuRepository();
final menuImportRepository = MenuImportRepository();
final orderRepository = OrderRepository();
final passkeyRepository = PasskeyRepository(auth: authRepository);
final statsRepository = StatsRepository();
final inviteRepository = InviteRepository();
final feedbackRepository = FeedbackRepository();
final auditLogRepository = AuditLogRepository();

/// Orders rung up with no connection, waiting on this device. Device-local and
/// never synced — see [PendingOrderQueue].
final pendingOrders = PendingOrderQueue(
  orders: orderRepository,
  stores: storeRepository,
);

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
class SessionException implements AppException {
  const SessionException(this.message);

  @override
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
  // Checked here rather than left to the first denied read. Everything the
  // rules grant is gated on `active`, so a removed member's next call is a
  // `permission-denied` on the store document — an error code where the honest
  // answer is a sentence. The document is watched, so this arrives the moment
  // a manager removes them rather than at the next cold start.
  if (!user.active) {
    throw const SessionException(
      'Your access to this shop has been removed.\n\n'
      'A manager can restore it, or you can sign in with another account.',
    );
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
