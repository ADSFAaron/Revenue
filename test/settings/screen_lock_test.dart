import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:Revenue/settings/screen_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The lock over Insights, exports, the staff list and the change history.
///
/// Everything worth testing here is about when it must NOT stand in the way.
/// It is a deterrent on an unattended counter, not a vault: a shop that cannot
/// reach its own takings because a sensor stopped answering has lost more than
/// the lock was ever protecting.
class _FakeAuth implements LocalAuthentication {
  _FakeAuth({this.supported = true, this.enrolled = true, this.allow = true});

  bool supported;
  bool enrolled;
  bool allow;

  /// Set to throw the way a missing platform implementation does.
  Object? failure;

  int prompts = 0;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> get canCheckBiometrics async => enrolled;

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
    expect(await lock.confirm('why'), isTrue);
    expect(auth.prompts, 0);
  });

  test('on, it asks, and a refusal is a refusal', () async {
    final auth = _FakeAuth(allow: false);
    final lock = await lockedWith(auth);

    expect(await lock.confirm('why'), isFalse);
    expect(auth.prompts, 1);
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

  test('signing out ends the grace period', () async {
    final auth = _FakeAuth();
    final lock = await lockedWith(auth);
    await lock.confirm('first');

    lock.relock();

    expect(await lock.confirm('second'), isTrue);
    expect(auth.prompts, 2, reason: 'the next person is a different person');
  });

  test('a device that cannot ask does not lock the shop out', () async {
    // Enrolment removed after the setting was turned on. Refusing here would
    // leave a shop unable to read its own figures with no way back.
    final auth = _FakeAuth(enrolled: false);
    final lock = await lockedWith(auth);

    expect(await lock.confirm('why'), isTrue);
    expect(auth.prompts, 0);
  });

  test('a platform failure is not a refusal', () async {
    final auth = _FakeAuth()..failure = StateError('no implementation');
    final lock = await lockedWith(auth);

    expect(await lock.confirm('why'), isTrue);
  });

  test('the setting survives a restart', () async {
    await (await lockedWith(_FakeAuth())).setEnabled(true);

    final next = ScreenLock(auth: _FakeAuth());
    await next.load();
    expect(next.value, isTrue);
  });
}
