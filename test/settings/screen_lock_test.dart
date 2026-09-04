import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:Revenue/settings/screen_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device-presence lock over the app's way in and over the screens that
/// show a shop's figures.
///
/// Most of what is pinned here is a bypass that shipped. The lock used to
/// answer a bool, and every path that could not run a prompt answered the
/// permissive one — so a tablet with a PIN and no fingerprint reader, and a
/// device whose platform channel threw, were both let straight through with
/// the lock switched on.
class _FakeAuth implements LocalAuthentication {
  _FakeAuth({
    this.supported = true,
    this.biometrics = const [BiometricType.fingerprint],
    this.allow = true,
  });

  bool supported;
  List<BiometricType> biometrics;
  bool allow;

  /// Set to throw the way a missing platform implementation does.
  Object? failure;

  int prompts = 0;
  int supportChecks = 0;

  @override
  Future<bool> isDeviceSupported() async {
    supportChecks++;
    return supported;
  }

  @override
  Future<bool> get canCheckBiometrics async => biometrics.isNotEmpty;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => biometrics;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object?> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    prompts++;
    if (failure != null) throw failure!;
    return allow;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ScreenLock> lockedWith(_FakeAuth auth) async {
    final lock = ScreenLock(auth: auth);
    await lock.setEnabled(true);
    lock.relock(); // setEnabled leaves a grace period; start from cold.
    return lock;
  }

  test('off by default, and asks nothing', () async {
    final auth = _FakeAuth();
    final lock = ScreenLock(auth: auth);
    await lock.load();

    expect(lock.value, isFalse);
    expect(await lock.check('why'), LockCheck.passed);
    expect(auth.prompts, 0);
  });

  test('on, it asks, and a refusal is a refusal', () async {
    final auth = _FakeAuth(allow: false);
    final lock = await lockedWith(auth);

    expect(await lock.check('why'), LockCheck.refused);
    expect(await lock.confirm('why'), isFalse);
    expect(auth.prompts, 2);
  });

  test('a PIN with no fingerprint reader still asks', () async {
    // The bypass this replaced. Availability was `isDeviceSupported() &&
    // canCheckBiometrics`, so a counter tablet with a passcode and no sensor —
    // an ordinary thing to find on a counter — reported that it could not lock
    // and was then let through unasked. `authenticate` is called with
    // `biometricOnly: false`, so the passcode was always going to work.
    final auth = _FakeAuth(biometrics: const []);
    final lock = await lockedWith(auth);

    expect(await lock.check('why'), LockCheck.passed);
    expect(auth.prompts, 1, reason: 'the passcode is a prompt worth raising');
  });

  test('a device with no secure lock at all cannot be asked', () async {
    final auth = _FakeAuth(supported: false);
    final lock = await lockedWith(auth);

    expect(await lock.check('why'), LockCheck.unavailable);
    expect(auth.prompts, 0);
  });

  test('a platform failure is unavailable, never a pass', () async {
    // This line used to `return true`. A device whose prompt failed to run let
    // anybody straight in, silently, with the lock on.
    final auth = _FakeAuth()..failure = StateError('no implementation');
    final lock = await lockedWith(auth);

    expect(await lock.check('why'), LockCheck.unavailable);
  });

  test('inside the app, a device that cannot ask does not lock the shop out',
      () async {
    // The gate at the way in is where an unaskable device is dealt with, once,
    // with the person told about it. Repeating that refusal on every screen
    // behind the gate would leave a shop unable to read its own takings with
    // nothing on screen to explain why.
    final auth = _FakeAuth(supported: false);
    final lock = await lockedWith(auth);

    expect(await lock.confirm('why'), isTrue);
    expect(auth.prompts, 0);
  });

  test('one unlock covers the next few minutes', () async {
    // Somebody reconciling a till moves between Insights, the change history
    // and an export in the same minute. A prompt on each is how a lock gets
    // switched off for good.
    final auth = _FakeAuth();
    final lock = await lockedWith(auth);

    expect(await lock.confirm('first'), isTrue);
    expect(await lock.confirm('second'), isTrue);
    expect(await lock.confirm('third'), isTrue);
    expect(auth.prompts, 1);
  });

  test('the way in never honours the grace period', () async {
    // The bypass that was reported from the counter: hand the till to a
    // colleague and take it straight back, and the second arrival landed
    // inside the first person's five minutes and walked in unasked.
    final auth = _FakeAuth();
    final lock = await lockedWith(auth);

    expect(await lock.check('in', allowGrace: false), LockCheck.passed);
    expect(await lock.check('back', allowGrace: false), LockCheck.passed);
    expect(auth.prompts, 2, reason: 'every arrival is asked');
  });

  test('signing out ends the grace period', () async {
    final auth = _FakeAuth();
    final lock = await lockedWith(auth);
    await lock.confirm('first');

    lock.relock();

    expect(await lock.confirm('second'), isTrue);
    expect(auth.prompts, 2, reason: 'the next person is a different person');
  });

  test('two checks at once share one prompt', () async {
    // Two `authenticate` calls at once is a platform error on Android, and the
    // app can produce it: a screen checking on the way in, mounted under a
    // cover that is also asking.
    final auth = _FakeAuth();
    final lock = await lockedWith(auth);

    final results = await Future.wait([
      lock.check('one', allowGrace: false),
      lock.check('two', allowGrace: false),
    ]);

    expect(results, [LockCheck.passed, LockCheck.passed]);
    expect(auth.prompts, 1);
  });

  test('coming back to the app re-reads whether the device can still ask',
      () async {
    // Enrolment can only be removed by leaving the app for Settings, so
    // returning is the one moment a cached "yes" could be wrong in the
    // direction that matters.
    final auth = _FakeAuth();
    final lock = await lockedWith(auth);
    await lock.check('first', allowGrace: false);
    expect(auth.supportChecks, 1);

    auth.supported = false;
    expect(await lock.check('cached', allowGrace: false), LockCheck.passed);

    lock.forgetAvailability();
    expect(await lock.check('after', allowGrace: false), LockCheck.unavailable);
  });

  test('the setting survives a restart', () async {
    await (await lockedWith(_FakeAuth())).setEnabled(true);

    final next = ScreenLock(auth: _FakeAuth());
    await next.load();
    expect(next.value, isTrue);
  });
}
