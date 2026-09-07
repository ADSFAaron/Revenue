import 'dart:async';

import 'package:flutter/foundation.dart';


export 'connection_status.dart' show ConnectionStatus, connectionStatus;
export 'pending_order_queue.dart' show PendingOrderQueue;

import '../models/app_user.dart';
import '../models/audit_log.dart';
import '../models/store.dart';
import 'audit_log_repository.dart';
import 'auth_repository.dart';
import 'data_exception.dart';
import 'device_accounts.dart';
import 'session_apps.dart';
import '../entry/idle_lock.dart';
import 'feedback_repository.dart';
import 'invite_repository.dart';
import 'menu_import_repository.dart';
import 'menu_repository.dart';
import 'order_repository.dart';
import 'order_slip_repository.dart';
import 'pending_order_queue.dart';
import 'passkey_repository.dart';
import 'stats_repository.dart';
import 'store_repository.dart';
import 'user_repository.dart';

export 'audit_log_repository.dart';
export 'auth_repository.dart';
export 'data_exception.dart';
export 'device_accounts.dart';
export 'session_apps.dart';
export 'feedback_repository.dart';
export 'invite_repository.dart';
export 'menu_import_repository.dart';
export 'menu_repository.dart';
export 'order_repository.dart';
export 'order_slip_repository.dart';
export 'passkey_repository.dart';
export 'stats_repository.dart';
export 'store_repository.dart';
export 'user_repository.dart';

/// The single entry point to stored data.
///
/// No widget may reach for `FirebaseFirestore.instance` or `FirebaseAuth`
/// directly. Keeping every query and every sign-in call behind these objects is
/// what makes the backend replaceable later without touching a single screen.
/// Signs the current operator out and hands the till to whoever else this
/// device is still holding a session for.
///
/// Every "log out" goes through this rather than through `signOut()` alone.
/// A device with three people signed in has three sessions to keep straight,
/// and one of them ending is not the same event as the till being empty.
Future<void> signOutOperator() async {
  final uid = authRepository.currentUid;
  await authRepository.signOut();
  if (uid != null) await sessionApps.release(uid);
}

/// Parks the operator at the till and opens a blank slot for somebody new.
///
/// Not a sign-out. The person stepping away stays signed in on their own slot,
/// so handing the till back to them later is a local switch that works with no
/// connection at all — which is the whole point of holding more than one.
Future<void> addAnotherOperator() => sessionApps.takeSlot();


// The repositories every screen reaches for.
//
// Reassignable, and there is exactly one reason for it. A screen calls
// `orderRepository.submit(...)` straight — no constructor argument, no
// provider, no lookup — and that is what keeps the call sites readable. The
// price, while these were `final`, was that a widget test had no way to put a
// fake in front of a screen: not one page in `lib/page/` or `lib/settings/`
// could be built by a test at all, because building it meant reaching a real
// Firebase. Two thirds of the app was therefore only ever checked by hand.
//
// Each is a getter over a nullable field rather than a variable with an
// initialiser, and that is not decoration. Several of these constructors call
// `FirebaseFunctions.instanceFor` or `FirebaseAuth.instanceFor`, which throw
// without an initialised Firebase app — so merely *reading* one of these names
// in a test builds something that cannot exist there. Null means "not built
// yet", [useRepositories] saves and restores the nulls, and a repository the
// app never touches is never constructed.
//
// **Nothing in `lib/` assigns to any of these.** They are written once, here,
// and by `test/journey/shop.dart`. If app code ever needs to swap one at
// runtime, that is a different problem and wants a different answer.

AuthRepository? _authRepository;
AuthRepository get authRepository => _authRepository ??= AuthRepository();
set authRepository(AuthRepository value) => _authRepository = value;

UserRepository? _userRepository;
UserRepository get userRepository =>
    _userRepository ??= UserRepository(auth: authRepository);
set userRepository(UserRepository value) => _userRepository = value;

StoreRepository? _storeRepository;
StoreRepository get storeRepository => _storeRepository ??= StoreRepository();
set storeRepository(StoreRepository value) => _storeRepository = value;

MenuRepository? _menuRepository;
MenuRepository get menuRepository => _menuRepository ??= MenuRepository();
set menuRepository(MenuRepository value) => _menuRepository = value;

MenuImportRepository? _menuImportRepository;
MenuImportRepository get menuImportRepository =>
    _menuImportRepository ??= MenuImportRepository();
set menuImportRepository(MenuImportRepository value) =>
    _menuImportRepository = value;

OrderRepository? _orderRepository;
OrderRepository get orderRepository => _orderRepository ??= OrderRepository();
set orderRepository(OrderRepository value) => _orderRepository = value;

OrderSlipRepository? _orderSlipRepository;
OrderSlipRepository get orderSlipRepository =>
    _orderSlipRepository ??= OrderSlipRepository();
set orderSlipRepository(OrderSlipRepository value) =>
    _orderSlipRepository = value;

PasskeyRepository? _passkeyRepository;
PasskeyRepository get passkeyRepository =>
    _passkeyRepository ??= PasskeyRepository(auth: authRepository);
set passkeyRepository(PasskeyRepository value) => _passkeyRepository = value;

StatsRepository? _statsRepository;
StatsRepository get statsRepository => _statsRepository ??= StatsRepository();
set statsRepository(StatsRepository value) => _statsRepository = value;

InviteRepository? _inviteRepository;
InviteRepository get inviteRepository =>
    _inviteRepository ??= InviteRepository();
set inviteRepository(InviteRepository value) => _inviteRepository = value;

FeedbackRepository? _feedbackRepository;
FeedbackRepository get feedbackRepository =>
    _feedbackRepository ??= FeedbackRepository();
set feedbackRepository(FeedbackRepository value) =>
    _feedbackRepository = value;

AuditLogRepository? _auditLogRepository;
AuditLogRepository get auditLogRepository =>
    _auditLogRepository ??= AuditLogRepository();
set auditLogRepository(AuditLogRepository value) =>
    _auditLogRepository = value;

/// Who uses this till. Local only — see [DeviceAccounts].
DeviceAccounts deviceAccounts = DeviceAccounts();

/// Orders rung up with no connection, waiting on this device. Device-local and
/// never synced — see [PendingOrderQueue].
///
/// Built from whatever [orderRepository] and [storeRepository] are when it is
/// first touched, so anything that replaces those has to replace this too.
/// [useRepositories] does; nothing else has any business changing it.
PendingOrderQueue? _pendingOrders;
PendingOrderQueue get pendingOrders => _pendingOrders ??= PendingOrderQueue(
      orders: orderRepository,
      stores: storeRepository,
    );
set pendingOrders(PendingOrderQueue value) => _pendingOrders = value;

/// Points the whole app at a different set of repositories, and hands back a
/// function that puts the originals back.
///
/// The one supported way to install fakes. It exists so that a test does not
/// have to know which of these hold references to which others —
/// [pendingOrders] captures two, [userRepository] and [passkeyRepository]
/// capture the auth one — and so that restoring is one call rather than a list
/// somebody will eventually get one short.
///
/// It also clears the session cache. [currentActor], [currentOperator] and
/// [idleTimeout] outlive a signed-in session by design, and a test that
/// inherited the previous test's operator would pass or fail for reasons
/// nothing in it mentions.
///
/// ```dart
/// addTearDown(useRepositories(auth: fakeAuth, orders: fakeOrders));
/// ```
@visibleForTesting
VoidCallback useRepositories({
  AuthRepository? auth,
  UserRepository? users,
  StoreRepository? stores,
  MenuRepository? menu,
  OrderRepository? orders,
  StatsRepository? stats,
  InviteRepository? invites,
  AuditLogRepository? auditLogs,
}) {
  // The *fields*, not the getters: reading a getter would build the real
  // repository this is being called to avoid ever building.
  final previous = (
    auth: _authRepository,
    users: _userRepository,
    stores: _storeRepository,
    menu: _menuRepository,
    orders: _orderRepository,
    stats: _statsRepository,
    invites: _inviteRepository,
    auditLogs: _auditLogRepository,
    passkeys: _passkeyRepository,
    pending: _pendingOrders,
    actor: _lastKnownActor,
    operator: currentOperator.value,
    idle: idleTimeout.value,
  );

  if (auth != null) _authRepository = auth;
  if (users != null) _userRepository = users;
  if (stores != null) _storeRepository = stores;
  if (menu != null) _menuRepository = menu;
  if (orders != null) _orderRepository = orders;
  if (stats != null) _statsRepository = stats;
  if (invites != null) _inviteRepository = invites;
  if (auditLogs != null) _auditLogRepository = auditLogs;
  // Holds the auth repository that has just been replaced, and building the
  // real one needs a Firebase app. Dropped rather than rebuilt: it is restored
  // below, and nothing that can be tested this way touches a passkey.
  _passkeyRepository = null;
  _pendingOrders = null;
  _lastKnownActor = null;
  currentOperator.value = null;
  idleTimeout.value = Duration.zero;

  return () {
    _authRepository = previous.auth;
    _userRepository = previous.users;
    _storeRepository = previous.stores;
    _menuRepository = previous.menu;
    _orderRepository = previous.orders;
    _statsRepository = previous.stats;
    _inviteRepository = previous.invites;
    _auditLogRepository = previous.auditLogs;
    _passkeyRepository = previous.passkeys;
    _pendingOrders = previous.pending;
    _lastKnownActor = previous.actor;
    currentOperator.value = previous.operator;
    idleTimeout.value = previous.idle;
  };
}

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
  const SessionException(this.message, {this.needsRegistration = false});

  @override
  final String message;

  /// True when the signed-in account has no profile document at all.
  ///
  /// Not a dead end, which is what it used to be presented as: the rules allow
  /// an account to create its own first `users/{uid}`, so this state is a
  /// registration that stopped halfway and can be carried on from. Everything
  /// else that lands here needs somebody else to fix it.
  final bool needsRegistration;

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
    // The old wording here sent people to "sign out and register again",
    // which cannot work: the account already exists, so registering again with
    // the same address is refused as `email-already-in-use`, and this screen
    // was the only thing between them and their own shop. The account is
    // signed in and the rules let it write its own first profile, so the way
    // out is forwards.
    throw SessionException(
      'Signed in as ${authRepository.currentEmail ?? uid}, but this account '
      'is not set up yet.\n\n'
      'This is what a registration that was interrupted leaves behind — the '
      'account was created, and the shop it belongs to was not. Carry on from '
      'where it stopped, either opening a store or joining one with an invite '
      'code.',
      needsRegistration: true,
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
  // Every way into the app ends here, which is why the device's roster is
  // updated here rather than on each of the four sign-in screens: one call
  // that cannot drift, and it records the identity the store has confirmed
  // rather than whatever the sign-in screen was told.
  unawaited(deviceAccounts.remember(user));
  // Ties this session to the slot it is running in, so the entry screen knows
  // that tapping this person's name is a local switch rather than a sign-in.
  unawaited(sessionApps.claimActive(user.uid));
  // The two things the shell above needs to know about whoever is holding the
  // tablet: their name, for the indicator on the order screen, and how long
  // the shop lets the till sit untouched.
  currentOperator.value = user;
  idleTimeout.value = Duration(minutes: store.idleTimeoutMinutes);
  return Session(user: user, store: store);
}
