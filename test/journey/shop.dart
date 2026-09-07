// A whole shop, in memory, for the journey tests.
//
// These tests exist because everything else in `test/` checks one piece in
// isolation, and a shop is not a pile of pieces. The failures that actually
// reach a counter live in the joins: an order that writes but never appears in
// history, a dish that is edited but read back from the wrong collection, a
// day's takings that count an edited order twice. None of those can be caught
// by testing `submit` alone, because `submit` is not what is wrong.
//
// So this harness wires the *real* repositories to a fake Firestore and a fake
// FirebaseAuth and lets a test drive them the way a shop does — register, add
// dishes, ring up, look at the history, look at the analytics. No emulator, no
// device, no network, so it runs on every `flutter test` rather than on the
// days somebody remembers to start one.
//
// What it deliberately does NOT prove:
//
//   * **Security rules.** Nothing here is denied. `firestore.rules` decides who
//     may do what, and it is Firestore that evaluates it, so it is tested where
//     a real Firestore can be reached — `test/rules/`, against the emulator.
//     A journey test passing means the app *asks* correctly, not that a
//     stranger would be refused.
//   * **Firebase Auth itself.** [FakeAuth] below checks passwords because our
//     screens branch on *which* failure came back, and that branching is ours
//     to get wrong. Whether Google's servers accept a password is not.
//   * **Cloud Functions.** `checkInvite`, the menu import and the slip reader
//     are callables. What runs behind them is tested in `functions/test/`.
//
// See `docs/testing.md` for the whole map, including what is left to a person.

import 'dart:async';

// `Order` is a name this app also uses, and cloud_firestore exports its own.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Revenue/database/audit_log_repository.dart';
import 'package:Revenue/database/repositories.dart' show useRepositories;
import 'package:Revenue/database/auth_repository.dart';
import 'package:Revenue/database/invite_repository.dart';
import 'package:Revenue/database/menu_repository.dart';
import 'package:Revenue/database/order_repository.dart';
import 'package:Revenue/database/stats_repository.dart';
import 'package:Revenue/database/store_repository.dart';
import 'package:Revenue/database/user_repository.dart';
import 'package:Revenue/models/app_user.dart';
import 'package:Revenue/models/audit_log.dart';
import 'package:Revenue/models/daily_stats.dart';
import 'package:Revenue/models/invite.dart';
import 'package:Revenue/models/menu_item.dart';
import 'package:Revenue/models/order.dart';
import 'package:Revenue/models/order_draft.dart';
import 'package:Revenue/models/store.dart';
import 'package:Revenue/theme.dart';

/// A shop with its own Firestore, its own accounts, and the real repositories
/// pointed at both.
///
/// Build one with [Shop.opened] — that runs the same provisioning the
/// registration screen runs, so a test starts from a shop that exists the way
/// a real one does rather than from documents hand-written into a fake.
class Shop {
  Shop._(FirebaseFirestore db, this.auth)
      // ignore: prefer_initializing_formals — `db` is also read by the
      // initialisers below, which a `this.db` parameter cannot be.
      : db = db,
        audit = AuditLogRepository(firestore: db),
        stores = StoreRepository(firestore: db),
        stats = StatsRepository(firestore: db) {
    authRepository = AuthRepository(auth: auth);
    users = UserRepository(firestore: db, auth: authRepository);
    menu = MenuRepository(firestore: db, auditLogs: audit);
    orders = OrderRepository(firestore: db, auditLogs: audit);
    invites = InviteRepository(firestore: db, functions: _UnusedFunctions());
  }

  /// The fake, wrapped so that transactions behave — see [_Firestore].
  final FirebaseFirestore db;
  final FakeAuth auth;

  final AuditLogRepository audit;
  final StoreRepository stores;
  final StatsRepository stats;
  late final AuthRepository authRepository;
  late final UserRepository users;
  late final MenuRepository menu;
  late final OrderRepository orders;
  late final InviteRepository invites;

  /// The store this shop is trading as. Re-read with [reloadStore] after a
  /// settings change — [Store] is immutable, so a stale copy would go on
  /// pricing orders at the old tax rate.
  late Store store;

  /// Whoever opened the shop.
  late AppUser owner;

  /// Opens a new store the way the registration screen does: create the
  /// account, write the owner's profile, then write the store.
  ///
  /// The order matters and is the order `lib/entry/open_store.dart` uses. A
  /// store written before its owner's profile is a shop nobody can get into.
  static Future<Shop> opened({
    String name = 'Test Noodles',
    String email = 'owner@example.com',
    String password = 'correct horse',
    String ownerName = 'Owner',
    Store Function(Store)? settings,
  }) async {
    final shop = Shop._(_Firestore(FakeFirebaseFirestore()), FakeAuth());
    await shop.register(
      email: email,
      password: password,
      displayName: ownerName,
      storeName: name,
      settings: settings,
    );
    return shop;
  }

  /// The provisioning half of "open a store", against whoever is signed in
  /// after [AuthRepository.register].
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String storeName,
    Store Function(Store)? settings,
  }) async {
    final uid = await authRepository.register(email: email, password: password);
    final storeId = db.collection('stores').doc().id;

    await users.create(AppUser(
      uid: uid,
      email: email,
      displayName: displayName,
      storeId: storeId,
      role: UserRole.owner,
    ));
    final fresh = Store(id: storeId, name: storeName);
    await stores.create(settings == null ? fresh : settings(fresh));

    owner = (await users.fetch(uid))!;
    store = (await stores.fetch(storeId))!;
  }

  /// Re-reads the store document. Call after anything that changes settings.
  Future<Store> reloadStore() async => store = (await stores.fetch(store.id))!;

  /// Points the app's own globals at this shop, so a real screen can be built.
  ///
  /// Everything in `lib/page/` and `lib/settings/` reaches
  /// `lib/database/repositories.dart` directly rather than being handed a
  /// repository, so this is what stands between a test and a screen. Call it
  /// before pumping a widget; the returned teardown is registered for you.
  ///
  /// Also fakes SharedPreferences, because `loadSession` — which every screen
  /// calls on the way in — updates the device's roster and its session slot
  /// through it. Both are fire-and-forget, so without this they fail silently
  /// on a missing plugin and the failure surfaces later as something else.
  void install() {
    SharedPreferences.setMockInitialValues({});
    addTearDown(useRepositories(
      auth: authRepository,
      users: users,
      stores: stores,
      menu: menu,
      orders: orders,
      stats: stats,
      invites: invites,
      auditLogs: audit,
    ));
  }

  /// The owner, as the thing an audit entry is stamped with.
  Actor get actor => Actor(uid: owner.uid, name: owner.displayName);

  /// A live code for somebody to join with, issued by the owner.
  Future<Invite> staffInvite({UserRole role = UserRole.staff}) => invites.create(
        storeId: store.id,
        storeName: store.name,
        role: role,
        createdBy: owner.uid,
      );

  /// The other way in: create an account, then spend an invite code on it.
  ///
  /// Mirrors `lib/entry/join_store.dart`. Note what it does *not* do —
  /// `InviteRepository.validate`, the callable the screen checks a code with
  /// before asking for a password. That is a Cloud Function and is out of
  /// reach here; [InviteRepository.redeem] is the write that actually decides
  /// the outcome, and it re-checks the code inside its own transaction, which
  /// is why a code can be checked from an unauthenticated screen without that
  /// being the thing keeping anybody out.
  ///
  /// Leaves the joiner signed in, the way the real flow does.
  Future<AppUser> join({
    required String code,
    required String email,
    required String password,
    required String displayName,
  }) async {
    final uid = await authRepository.register(email: email, password: password);
    try {
      await invites.redeem(
        code: code,
        uid: uid,
        email: email,
        displayName: displayName,
      );
    } catch (_) {
      // What the screen does when redemption fails: the account it just made
      // is deleted rather than left behind as one that can sign in and reach
      // nothing. Modelled as a sign-out because [FakeAuth] has no accounts to
      // delete — what matters to the assertions is that no profile was written.
      await authRepository.signOut();
      rethrow;
    }
    return (await users.fetch(uid))!;
  }

  /// Signs a second person in and returns their profile.
  ///
  /// Sign-in is a real call through [AuthRepository] rather than a poke at the
  /// fake, because "which account is current" is what decides who a write is
  /// attributed to, and that is worth going through the front door for.
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final uid = await authRepository.signIn(email: email, password: password);
    return (await users.fetch(uid))!;
  }

  /// Adds a dish and returns it with the id Firestore gave it.
  Future<MenuItem> addDish(
    String name, {
    int price = 100,
    int cost = 0,
    String? categoryId,
    int sortOrder = 0,
  }) async {
    final id = await menu.add(
      store.id,
      MenuItem(
        id: '',
        name: name,
        price: price,
        cost: cost,
        categoryId: categoryId,
        sortOrder: sortOrder,
      ),
    );
    return (await menu.fetchAll(store.id)).firstWhere((i) => i.id == id);
  }

  /// A moment at [hour] inside the store's *current trading day*.
  ///
  /// Not `DateTime.now().copyWith(hour: ...)`, which is the trap this exists
  /// to close. A trading day is shifted by the store's cutoff — with the
  /// default of 04:00, a test running at 00:30 is in the trading day that
  /// began yesterday morning, so "noon today" by the wall clock belongs to
  /// *tomorrow's* rollup and `dayStats()` reads an empty one. Tests written
  /// the obvious way therefore pass all day and fail between midnight and the
  /// cutoff, which is the worst kind of test to own.
  DateTime atHour(int hour) {
    final dayStart = parseBusinessDate(store.currentBusinessDate);
    final candidate = dayStart.add(Duration(hours: hour));
    return store.businessDateOf(candidate) == store.currentBusinessDate
        ? candidate
        : candidate.add(const Duration(days: 1));
  }

  /// Rings up an order and returns the number it was given.
  ///
  /// [at] is the moment of sale, which is not always now: half of what the
  /// analytics and the correction window do depends on *when* an order was
  /// placed, and a test that can only place orders at the current instant
  /// cannot reach any of it.
  Future<int> ringUp(
    List<(MenuItem, int)> lines, {
    DateTime? at,
    String? by,
    int guestCount = 1,
    String? paymentMethodId,
    OrderChannel channel = OrderChannel.dineIn,
  }) =>
      orders.submit(
        store: store,
        createdBy: by ?? owner.uid,
        draft: OrderDraft(
          placedAt: at ?? DateTime.now(),
          guestCount: guestCount,
          channel: channel,
          paymentMethodId: paymentMethodId ?? store.defaultPaymentMethodId,
          items: [
            for (final (item, qty) in lines)
              OrderLine(
                itemId: item.id,
                name: item.name,
                categoryId: item.categoryId,
                unitPrice: item.price,
                unitCost: item.cost,
                qty: qty,
              ),
          ],
        ),
      );

  /// Corrects an existing order to a new set of lines.
  ///
  /// This is what the order-detail screen's Edit does once [mayChangeOrder]
  /// has let it through. Whether it *should* be let through is a separate
  /// question and is decided by that function and by `firestore.rules`; this
  /// makes the change itself, so a test can check what an allowed edit leaves
  /// behind.
  Future<int> edit(
    Order order,
    List<(MenuItem, int)> lines, {
    Actor? by,
    DateTime? at,
  }) =>
      orders.replace(
        store: store,
        orderId: order.id,
        by: by,
        draft: OrderDraft(
          placedAt: at ?? order.placedAt,
          guestCount: order.guestCount,
          channel: order.channel,
          paymentMethodId: order.paymentMethodId,
          items: [
            for (final (item, qty) in lines)
              OrderLine(
                itemId: item.id,
                name: item.name,
                categoryId: item.categoryId,
                unitPrice: item.price,
                unitCost: item.cost,
                qty: qty,
              ),
          ],
        ),
      );

  // ------------------------------------------------------------------
  // Reads that are safe inside `testWidgets`.
  //
  // A widget test runs against a fake clock that only advances when the test
  // pumps, so the watch-based reads further down never settle when awaited
  // from a test body — and a hang there kills the whole test *file*, reporting
  // every test after it as "did not complete". Everything in this section is a
  // one-shot `get` with no timers behind it. Use these to check what a screen
  // actually wrote.
  // ------------------------------------------------------------------

  /// The store document as it stands now, without disturbing [store].
  Future<Store> storeNow() async => (await stores.fetch(store.id))!;

  /// Every dish, retired ones included.
  Future<List<MenuItem>> menuNow() => menu.fetchAll(store.id);

  /// One person's profile as it stands now.
  Future<AppUser> userNow(String uid) async => (await users.fetch(uid))!;

  /// Today's rollup.
  Future<DailyStats> dayStatsNow([String? businessDate]) async {
    final doc = await db
        .collection('stores')
        .doc(store.id)
        .collection('dailyStats')
        .doc(businessDate ?? store.currentBusinessDate)
        .get();
    return doc.exists
        ? DailyStats.fromDoc(doc)
        : DailyStats(businessDate: businessDate ?? store.currentBusinessDate);
  }

  /// Every order, newest first.
  Future<List<Order>> ordersNow() async {
    final snap = await db
        .collection('stores')
        .doc(store.id)
        .collection('orders')
        .orderBy('placedAt', descending: true)
        .get();
    return snap.docs.map(Order.fromDoc).toList();
  }

  /// Every audit entry.
  Future<List<AuditLog>> auditNow() async {
    final snap = await db
        .collection('stores')
        .doc(store.id)
        .collection('auditLogs')
        .get();
    return snap.docs.map(AuditLog.fromDoc).toList();
  }

  /// Every invite code issued for this store.
  Future<List<Invite>> invitesNow() async {
    final snap = await db
        .collection('invites')
        .where('storeId', isEqualTo: store.id)
        .get();
    return snap.docs.map(Invite.fromDoc).toList();
  }

  /// The newest order, read with a one-shot `get` rather than a watch.
  ///
  /// For use inside `testWidgets`. The stream-based reads below settle by
  /// turning the event loop, and a widget test runs against a fake clock where
  /// the fake's stream plumbing does not advance unless the test pumps — so a
  /// watch awaited from a widget test's body hangs until the runner kills the
  /// whole file. A `get` has no such machinery behind it.
  Future<Order> newestOrder() async {
    final snap = await db
        .collection('stores')
        .doc(store.id)
        .collection('orders')
        .orderBy('placedAt', descending: true)
        .limit(1)
        .get();
    return Order.fromDoc(snap.docs.single);
  }

  /// The order history, newest first — the same read the history screen makes.
  Future<List<Order>> history({int limit = 20}) async =>
      (await _settled(orders.watchRecent(store.id, limit: limit)));

  /// Today's rollup, the one the home screen and the day view read.
  Future<DailyStats> dayStats([String? businessDate]) => _settled(
        stats.watchDay(store.id, businessDate ?? store.currentBusinessDate),
      );

  /// Every audit entry written so far, newest first.
  Future<List<AuditLog>> auditLog() => _settled(audit.watchRecent(store.id));

  /// What a watch is showing once it has stopped changing.
  ///
  /// Not `.first`, which is the trap here. `fake_cloud_firestore` gives a new
  /// listener a stale value before the current one — subscribe right after a
  /// write and the first thing through is the state from before it, so a shop
  /// that has just rung up a sale reads back takings of zero. The app never
  /// sees this: it subscribes once, on the way into a screen, and stays
  /// subscribed while the values arrive. A test asking a fresh stream for
  /// exactly one value is the artificial part, so this waits for the stream to
  /// go quiet and answers with the last thing it said.
  ///
  /// Ten turns of the microtask queue, not a wall-clock wait: everything
  /// behind these streams is in memory, so anything still pending after ten
  /// turns is not slow, it is stuck, and a test should say so rather than
  /// hang.
  ///
  /// Microtasks specifically, never `Future.delayed`. Inside `testWidgets` the
  /// body runs against a fake clock that only advances when the test pumps, so
  /// a `Future.delayed(Duration.zero)` awaited there never completes and the
  /// whole test file hangs until the runner kills it. Microtasks drain the
  /// same way in both worlds.
  Future<T> _settled<T>(Stream<T> watch) async {
    T? latest;
    var seen = false;
    final sub = watch.listen((value) {
      latest = value;
      seen = true;
    });
    for (var turn = 0; turn < 10; turn++) {
      await Future<void>.microtask(() {});
    }
    // Not awaited. Cancelling one of the fake's subscriptions can wait on
    // machinery that a widget test's clock never runs, and a harness helper
    // that hangs takes the whole test *file* down with it — the runner kills
    // the shell and every test after it is reported as not having completed,
    // which points nowhere near the line that caused it.
    unawaited(sub.cancel());
    if (!seen) {
      throw StateError(
        'The watch produced no value. Inside `testWidgets`, use a screen or '
        '`newestOrder()` instead: a widget test runs against a fake clock, and '
        'the streams behind these helpers only advance when the test pumps.',
      );
    }
    return latest as T;
  }
}

/// A [FirebaseAuth] that remembers passwords.
///
/// `firebase_auth_mocks` hands back a signed-in user for any credentials at
/// all, which makes "signing in with the wrong password" untestable — and the
/// wrong password is the case the screens have the most to say about. This
/// keeps an email-to-password book and throws the same
/// [FirebaseAuthException] codes Firebase throws, because those codes are what
/// `AuthRepository._translate` reads and what every sign-in screen branches on.
///
/// Everything else on the interface is left to [noSuchMethod]: a test that
/// reaches a part of Firebase Auth this does not model should fail loudly
/// rather than quietly get null.
class FakeAuth implements FirebaseAuth {
  final Map<String, String> _passwords = {};
  final Map<String, MockUser> _accounts = {};
  final _states = StreamController<User?>.broadcast();

  MockUser? _current;

  /// Firebase's own minimum. Enforced here because registration puts "password
  /// too short" under the password field, and that branch needs a way to fire.
  static const int minimumPasswordLength = 6;

  @override
  User? get currentUser => _current;

  @override
  Stream<User?> authStateChanges() => _states.stream;

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (password.length < minimumPasswordLength) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password should be at least 6 characters',
      );
    }
    if (_passwords.containsKey(email)) {
      throw FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'The email address is already in use by another account.',
      );
    }
    _passwords[email] = password;
    final user = MockUser(
      uid: 'uid-${_accounts.length + 1}',
      email: email,
      // What `AuthRepository.hasPasswordSignIn` reads. An account made this
      // way has a password; one made by Google does not, and offering to
      // change a password that does not exist is the bug that check exists to
      // stop.
      providerData: [_PasswordProvider()],
    );
    _accounts[email] = user;
    return _signedIn(user);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final known = _passwords[email];
    if (known == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'There is no user record corresponding to this identifier.',
      );
    }
    if (known != password) {
      // Firebase collapsed `wrong-password` into `invalid-credential` so that a
      // wrong password and an unknown address are indistinguishable to anybody
      // fishing for which addresses have accounts. The app has to read the new
      // code, so the fake throws the new code.
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'The supplied auth credential is incorrect or has expired.',
      );
    }
    return _signedIn(_accounts[email]!);
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _states.add(null);
  }

  Future<UserCredential> _signedIn(MockUser user) async {
    _current = user;
    _states.add(user);
    return _Credential(user);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'FakeAuth does not model ${invocation.memberName}. '
        'Add it here if a journey needs it.',
      );
}

class _Credential implements UserCredential {
  _Credential(this.user);

  @override
  final User user;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not modelled.');
}

/// The one entry in a password account's `providerData`.
///
/// `UserInfo`'s constructor is `@protected`, so it cannot be built here without
/// the analyzer objecting — and `providerId` is the only field anything in this
/// app reads off it.
class _PasswordProvider implements UserInfo {
  @override
  String get providerId => 'password';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not modelled.');
}

/// A [FakeFirebaseFirestore] with transactions that behave like Firestore's.
///
/// `fake_cloud_firestore` runs a transaction handler against a stand-in that
/// throws its [SetOptions] away — every `tx.set(ref, data, SetOptions(merge:
/// true))` lands as a whole-document replace. That is not an obscure corner
/// for this app: the daily rollup is written exactly that way, as a merge of
/// `FieldValue.increment`s, so under the plain fake a shop's second order of
/// the day *replaces* the first instead of adding to it and the day's takings
/// read as whatever the last order was. Tests written against that would have
/// been asserting a fake's bug.
///
/// So the two things Firestore actually promises are put back: writes carry
/// their options, and they are buffered until the handler returns rather than
/// being applied as it runs. Everything else is the fake, untouched — only
/// [collection], [batch] and [runTransaction] are reached from `lib/database`,
/// and anything else raises rather than quietly doing nothing.
class _Firestore implements FirebaseFirestore {
  _Firestore(this.fake);

  final FakeFirebaseFirestore fake;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      fake.collection(path);

  @override
  WriteBatch batch() => fake.batch();

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final transaction = _Transaction();
    final result = await handler(transaction);
    await transaction._commit();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'The journey harness does not forward ${invocation.memberName} to the '
        'fake. Add it here if a repository starts using it.',
      );
}

/// Reads straight through; writes wait for the commit, with their options.
class _Transaction implements Transaction {
  final _writes = <Future<void> Function()>[];

  /// Firestore refuses a read issued after a write in the same transaction,
  /// and so does this — the repositories are written to that rule and it is
  /// worth keeping them honest about it.
  bool _written = false;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
      DocumentReference<T> reference) {
    if (_written) {
      throw StateError(
        'Firestore transactions require all reads before all writes.',
      );
    }
    return reference.get();
  }

  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    _written = true;
    _writes.add(() => reference.set(data, options));
    return this;
  }

  @override
  Transaction update(
    DocumentReference reference,
    Map<Object, Object?> data,
  ) {
    _written = true;
    _writes.add(() => reference.update(data));
    return this;
  }

  @override
  Transaction delete(DocumentReference reference) {
    _written = true;
    _writes.add(() => reference.delete());
    return this;
  }

  Future<void> _commit() async {
    for (final write in _writes) {
      await write();
    }
    _writes.clear();
  }
}

/// Stands in for Cloud Functions, which no journey may reach.
///
/// [InviteRepository] builds a real `FirebaseFunctions` in its constructor
/// unless it is handed one, and that call needs an initialised Firebase app.
/// Passing this keeps the constructor cheap and makes any test that strays
/// into a callable say so.
class _UnusedFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Journey tests do not call Cloud Functions — see functions/test/.',
      );
}

/// Mounts a screen the way the app does, and lets its first reads land.
///
/// Deliberately not `pumpAndSettle`. The till screen holds a one-minute
/// `Timer.periodic` for its clock and the opening animation runs on another,
/// so there is always a next frame and settling never finishes. Twenty frames
/// is enough for the nested streams and futures behind these pages to deliver;
/// anything still pending after that is not slow, it is stuck.
Future<void> showScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(
    theme: const MaterialTheme(TextTheme()).light(),
    home: screen,
  ));
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Whether the button carrying this label can be pressed.
///
/// `byWidgetPredicate` rather than `byType`: `find.byType` matches the exact
/// runtime type, and `ButtonStyleButton` is abstract, so asking for it by type
/// finds nothing at all — including on a screen where the buttons are plainly
/// there.
bool buttonEnabled(WidgetTester tester, String label) {
  final button = tester.widget<ButtonStyleButton>(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
  );
  return button.onPressed != null;
}
