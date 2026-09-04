import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/database/device_accounts.dart';
import 'package:Revenue/models/app_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The roster the operator picker is built on.
///
/// It holds no credential, so nothing here is a security boundary. What it can
/// get wrong is losing people, and that is what these pin down: a shared till
/// whose list of names silently shortens is worse than no list, because the
/// person who has vanished from it goes back to sharing somebody else's login.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppUser person(String uid, {String name = '', String email = ''}) => AppUser(
        uid: uid,
        displayName: name.isEmpty ? uid : name,
        email: email.isEmpty ? '$uid@example.test' : email,
        storeId: 'store-1',
      );

  Future<DeviceAccounts> fresh([Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    final accounts = DeviceAccounts(prefs: await SharedPreferences.getInstance());
    await accounts.load();
    return accounts;
  }

  test('remembers people most recently used first', () async {
    final roster = await fresh();
    await roster.remember(person('a'));
    await roster.remember(person('b'));
    await roster.remember(person('a'));

    expect(roster.accounts.map((a) => a.uid), ['a', 'b']);
  });

  test('a write arriving before the first read keeps the others', () async {
    // The failure this exists for: `loadSession()` records whoever just signed
    // in, and it can fire before anything has asked the roster to load. A
    // mutator that wrote its own single entry over an unread roster would take
    // a four-person till down to one, quietly.
    SharedPreferences.setMockInitialValues({});
    final seeded = DeviceAccounts(prefs: await SharedPreferences.getInstance());
    await seeded.remember(person('a'));
    await seeded.remember(person('b'));

    final unread = DeviceAccounts(prefs: await SharedPreferences.getInstance());
    expect(unread.isLoaded, isFalse);
    await unread.remember(person('c'));

    expect(unread.accounts.map((a) => a.uid), ['c', 'b', 'a']);
  });

  test('a passkey learned before the name lands ends up on one entry',
      () async {
    // A passkey sign-in knows the credential before the session has resolved
    // who owns it, so the two arrive in that order and must not become two
    // people.
    final roster = await fresh();
    await roster.rememberPasskey('a', 'cred-1');
    await roster.remember(person('a', name: 'Ah-Ming'));

    expect(roster.accounts, hasLength(1));
    expect(roster.accounts.single.passkeyIds, ['cred-1']);
    expect(roster.accounts.single.label, 'Ah-Ming');
  });

  test('the same credential is not recorded twice', () async {
    final roster = await fresh();
    await roster.remember(person('a'));
    await roster.rememberPasskey('a', 'cred-1');
    await roster.rememberPasskey('a', 'cred-1');

    expect(roster.accounts.single.passkeyIds, ['cred-1']);
  });

  test('forgetting passkeys leaves the person', () async {
    // What happens when the authenticator says it holds none of them: the fast
    // path is wrong, the name is still right.
    final roster = await fresh();
    await roster.remember(person('a'));
    await roster.rememberPasskey('a', 'cred-1');
    await roster.forgetPasskeys('a');

    expect(roster.accounts.single.passkeyIds, isEmpty);
    expect(roster.accounts, hasLength(1));
  });

  test('forgetting a person takes only them', () async {
    final roster = await fresh();
    await roster.remember(person('a'));
    await roster.remember(person('b'));
    await roster.forget('a');

    expect(roster.accounts.map((a) => a.uid), ['b']);
  });

  test('survives a restart', () async {
    final first = await fresh();
    await first.remember(person('a', name: 'Ah-Ming'));
    await first.rememberPasskey('a', 'cred-1');

    final second =
        DeviceAccounts(prefs: await SharedPreferences.getInstance());
    await second.load();

    expect(second.accounts.single.label, 'Ah-Ming');
    expect(second.accounts.single.passkeyIds, ['cred-1']);
  });

  test('a roster that will not parse is an empty one, not a crash', () async {
    final roster = await fresh({'device_accounts': 'not json at all'});
    expect(roster.accounts, isEmpty);
  });
}
