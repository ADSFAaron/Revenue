import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a lock check came back with.
///
/// Three answers rather than two, because "the device could not ask" is not
/// the same event as "the person could not get past it" and the two want
/// opposite handling. Collapsing them into a bool is what made the lock
/// openable by anybody: every path that could not run a prompt answered
/// `true`, so a device with no enrolment, or a platform channel that threw,
/// read as a successful unlock.
enum LockCheck {
  /// The lock is off, or somebody just proved they are holding the device.
  passed,

  /// Asked, and did not get past it — cancelled, or the wrong finger.
  refused,

  /// The lock is on and this device cannot ask. Enrolment was removed after
  /// the setting was turned on, or the platform failed to run the prompt.
  unavailable,
}

/// A **device presence** check over the screens that show a shop's figures.
///
/// **This is not authentication, and it is not a passkey.** The two get
/// confused because both start with a fingerprint, and they answer different
/// questions:
///
/// - A **passkey** ([PasskeyRepository]) is a credential. It proves *who* is
///   signing in, to Firebase, against a key that only this person's
///   authenticator holds. It creates a session.
/// - This is a **device lock**. It proves only that somebody who can open this
///   device is holding it right now. Android and iOS return success or failure
///   and nothing else — no platform says which finger was used — so on a
///   shared counter tablet any enrolled finger passes it, whoever they are.
///   It creates nothing and identifies nobody.
///
/// So this must never be offered as a way of signing in, and a session must
/// never be granted on the strength of it. What it is for is the most likely
/// thing that actually goes wrong in a food shop: a till left signed in on a
/// counter, in reach of anybody who walks behind it. Because the session
/// outlives being closed — which is right for a till — opening the app is
/// exactly where that ask belongs, and the app is held back until it passes
/// rather than drawn and covered over. See docs/auth-and-operator-plan.md §2.1.
///
/// Per device rather than per account, and off by default. The lock belongs to
/// the tablet on the counter, not to the owner's own phone, and a shop with
/// one person in it gains nothing from being asked.
class ScreenLock extends ValueNotifier<bool> {
  ScreenLock({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication(),
        super(false);

  static const _key = 'screen_lock_enabled';

  /// How long one unlock lasts *inside* the app. Somebody reconciling a till
  /// moves between Insights, the change history and an export in the same
  /// minute, and a prompt on each of those is how a lock gets turned off.
  ///
  /// The gate at the way in does not honour it — see [check]'s `allowGrace`.
  static const Duration grace = Duration(minutes: 5);

  final LocalAuthentication _auth;

  DateTime? _unlockedUntil;

  /// The prompt currently on screen, if any.
  ///
  /// Two `authenticate` calls at once is a platform error on Android, and the
  /// loser is the second one — which is the app's own cover asking, while a
  /// screen underneath asks on the way in. The second caller waits for the
  /// first answer instead of racing it.
  Future<LockCheck>? _running;

  /// Whether this device can ask at all.
  ///
  /// Cached, and dropped whenever the app comes back to the front — enrolment
  /// can only be removed by leaving the app for Settings, and coming back is
  /// the moment a stale `true` would matter.
  Future<bool>? _available;

  Future<bool> get isAvailable => _available ??= _resolveAvailability();

  void forgetAvailability() => _available = null;

  /// Lets a test say what this device can do with no platform behind it.
  ///
  /// `local_auth` has no implementation under `flutter_test`, and a call into
  /// it never answers rather than failing — so a widget test of the gate would
  /// sit on a spinner for ever instead of exercising the branch it is for.
  @visibleForTesting
  void debugSetAvailable(bool available) =>
      _available = Future<bool>.value(available);

  /// Whether a finger or a face is enrolled, as opposed to only a PIN.
  ///
  /// For wording alone. The lock accepts either, so nothing branches on this.
  Future<bool> get hasBiometrics async {
    if (kIsWeb) return false;
    try {
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _resolveAvailability() async {
    if (kIsWeb) return false;
    try {
      // `isDeviceSupported()` is the whole question, because [authenticate] is
      // called with `biometricOnly: false`: it is true when the device can
      // check a biometric *or* fall back to its PIN, pattern or passcode, and
      // false when the device has no secure lock at all.
      //
      // This used to be `isDeviceSupported() && canCheckBiometrics`, which
      // answered a different question. A counter tablet with a PIN and no
      // fingerprint reader — an ordinary thing to find on a counter — reported
      // "this device cannot lock" and was then let straight through, with the
      // lock switched on and a cover on screen that asked for nothing.
      return await _auth.isDeviceSupported();
    } catch (_) {
      // A missing platform implementation throws rather than answering.
      return false;
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getBool(_key) ?? false;
    } catch (_) {
      value = false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    value = enabled;
    // Turning it on counts as having just proved yourself — the prompt that
    // enabled it was a second ago.
    _unlockedUntil = enabled ? DateTime.now().add(grace) : null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    } catch (_) {
      // The setting failing to persist is worth less than the screen the
      // person was on. It applies for this run either way.
    }
  }

  /// Forgets any grace period.
  ///
  /// Called wherever the person in front of the device may have changed: a
  /// sign-out, and every arrival at the gate.
  void relock() => _unlockedUntil = null;

  /// Asks, unless there is a standing reason not to.
  ///
  /// [allowGrace] is false at the way in. The five minutes exist so that
  /// moving between two screens inside the app is not two prompts; letting the
  /// *gate* honour them meant handing the till to a colleague and taking it
  /// straight back walked in unasked, because the second arrival was still
  /// inside the first one's grace.
  Future<LockCheck> check(String reason, {bool allowGrace = true}) async {
    if (!value) return LockCheck.passed;

    if (allowGrace) {
      final until = _unlockedUntil;
      if (until != null && DateTime.now().isBefore(until)) {
        return LockCheck.passed;
      }
    }

    if (!await isAvailable) return LockCheck.unavailable;

    final running = _running;
    if (running != null) return running;
    final future = _prompt(reason);
    _running = future;
    try {
      return await future;
    } finally {
      _running = null;
    }
  }

  Future<LockCheck> _prompt(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        // The device passcode is allowed as a fallback on purpose: a wet or
        // floury finger is a normal state behind a counter, and a lock that
        // cannot be got past in that state is a lock somebody switches off.
        biometricOnly: false,
        // The platform stops an authentication when the app is backgrounded,
        // which on a till happens for a card terminal or a notification. Retry
        // on the way back rather than failing at it.
        persistAcrossBackgrounding: true,
      );
      if (ok) _unlockedUntil = DateTime.now().add(grace);
      return ok ? LockCheck.passed : LockCheck.refused;
    } catch (e) {
      // Was `return true`, which is the single worst line this file could
      // have held: a device whose prompt failed to run let anybody straight
      // through, silently, with the lock switched on and nothing on screen to
      // say the lock had not been applied. It is reported as unavailable, and
      // the gate at the way in is what deals with that.
      debugPrint('Screen lock could not ask: $e');
      return LockCheck.unavailable;
    }
  }

  /// True when a screen *inside* the app may open.
  ///
  /// [LockCheck.unavailable] passes here, and only here. A device that can no
  /// longer ask is dealt with once, at the gate, with the person told about it
  /// and given a way to fix it; repeating that refusal on every screen behind
  /// the gate would lock a shop out of its own figures with nothing on screen
  /// to explain why.
  Future<bool> confirm(String reason) async =>
      await check(reason) != LockCheck.refused;
}

/// The one instance. Loaded in `main()` alongside the theme, because both are
/// a single key out of shared_preferences and both are needed before the first
/// screen that consults them.
final screenLock = ScreenLock();
