import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/database/session_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bookkeeping behind holding several operators signed in at once.
///
/// What Firebase does with the apps cannot be tested here — that needs a real
/// device and a real project. What can be, and is the part that decides
/// whether a shop's till behaves, is which slot each person is in and who is
/// holding it after somebody signs out.
class _FakeApp implements FirebaseApp {
  _FakeApp(this.name);

  @override
  final String name;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> opened;
  late List<String> signedOut;

  Future<SessionApps> fresh([Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    opened = [];
    signedOut = [];
    final apps = SessionApps(
      prefs: await SharedPreferences.getInstance(),
      open: (slot) async {
        opened.add(slot);
        return _FakeApp(slot);
      },
      signOut: (app) async => signedOut.add(app.name),
    );
    await apps.start();
    return apps;
  }

  test('a device with one person on it opens one app', () async {
    final apps = await fresh();

    expect(opened, [SessionApps.defaultSlot]);
    expect(apps.activeSlot, SessionApps.defaultSlot);
    expect(apps.active.name, SessionApps.defaultSlot);
  });

  test('a second operator gets a slot of their own, and the first keeps theirs',
      () async {
    final apps = await fresh();
    await apps.claimActive('ming');

    // Parking rather than signing out is the whole point: Ming stays signed in
    // on the slot he was using.
    await apps.takeSlot();
    await apps.claimActive('mei');

    expect(apps.holdsSessionFor('ming'), isTrue);
    expect(apps.holdsSessionFor('mei'), isTrue);
    expect(signedOut, isEmpty);
    expect(apps.activeSlot, isNot(SessionApps.defaultSlot));
  });

  test('switching back to a held session opens no new app and asks nobody',
      () async {
    final apps = await fresh();
    await apps.claimActive('ming');
    await apps.takeSlot();
    await apps.claimActive('mei');

    final before = opened.length;
    expect(await apps.switchTo('ming'), isTrue);

    expect(apps.activeSlot, SessionApps.defaultSlot);
    expect(opened.length, before, reason: 'the slot was already open');
    expect(signedOut, isEmpty);
  });

  test('somebody this device has never held is not a switch', () async {
    final apps = await fresh();
    expect(await apps.switchTo('a-stranger'), isFalse);
  });

  test('the till changing hands is announced once', () async {
    final apps = await fresh();
    await apps.claimActive('ming');
    await apps.takeSlot();
    await apps.claimActive('mei');

    final seen = <int>[];
    apps.revision.addListener(() => seen.add(apps.revision.value));

    await apps.switchTo('ming');
    await apps.switchTo('ming'); // already current

    expect(seen, hasLength(1),
        reason: 'a switch to the slot already active is not a change');
  });

  test('signing out hands the till to whoever else is on the device',
      () async {
    final apps = await fresh();
    await apps.claimActive('ming');
    await apps.takeSlot();
    await apps.claimActive('mei');

    expect(await apps.release('mei'), 'ming');
    expect(apps.holdsSessionFor('mei'), isFalse);
    expect(apps.activeSlot, SessionApps.defaultSlot);
  });

  test('the last person out leaves nobody at the till', () async {
    final apps = await fresh();
    await apps.claimActive('ming');

    expect(await apps.release('ming'), isNull);
    expect(apps.liveUids, isEmpty);
  });

  test('a fifth operator costs the longest-standing one their slot', () async {
    final apps = await fresh();
    for (final uid in ['a', 'b', 'c', 'd']) {
      await apps.claimActive(uid);
      if (uid != 'd') await apps.takeSlot();
    }
    expect(apps.liveUids, hasLength(SessionApps.maxSlots));

    await apps.takeSlot();
    await apps.claimActive('e');

    expect(apps.holdsSessionFor('a'), isFalse);
    expect(signedOut, ['default'], reason: 'the evicted session is ended');
    expect(apps.liveUids, hasLength(SessionApps.maxSlots));
  });

  test('who is where survives a restart', () async {
    final apps = await fresh();
    await apps.claimActive('ming');
    await apps.takeSlot();
    await apps.claimActive('mei');
    final slot = apps.activeSlot;

    final next = SessionApps(
      prefs: await SharedPreferences.getInstance(),
      open: (s) async => _FakeApp(s),
    );
    await next.start();

    expect(next.activeSlot, slot);
    expect(next.holdsSessionFor('ming'), isTrue);
    expect(next.holdsSessionFor('mei'), isTrue);
  });

  test('a slot name it no longer recognises is ignored', () async {
    // A build that changed the slot names must not resolve a stale one into an
    // app nobody can open.
    final apps = await fresh({
      'session.slots': <String>['ming gone-slot'],
      'session.active': 'gone-slot',
    });

    expect(apps.activeSlot, SessionApps.defaultSlot);
    expect(apps.holdsSessionFor('ming'), isFalse);
  });
}
