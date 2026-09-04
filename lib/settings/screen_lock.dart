import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device lock over the screens that show a shop's figures and its people.
///
/// **This is not authentication and must never be presented as it.** A
/// fingerprint says the tablet is not currently unattended; it does not say
/// who is holding it. Android and iOS both return success or failure and
/// nothing else — no platform exposes which finger was used — so any enrolled
/// finger on a shared counter tablet opens any of these screens. See
/// docs/auth-and-operator-plan.md §2.1.
///
/// What it is for is the most likely thing that actually goes wrong in a food
/// shop, which is not a stolen password: it is a till left signed in on a
/// counter, in reach of anybody who walks behind it. That is the case
/// two-factor authentication does nothing about and this does.
///
/// Per device rather than per account, and off by default. The lock belongs to
/// the tablet on the counter, not to the owner's own phone, and a shop with
/// one person in it gains nothing from being asked.
class ScreenLock extends ValueNotifier<bool> {
  ScreenLock({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication(),
        super(false);

  static const _key = 'screen_lock_enabled';

  /// How long one unlock lasts. Somebody reconciling a till moves between
  /// Insights, the change history and an export in the same minute, and a
  /// prompt on each of those is how a lock gets turned off.
  static const Duration grace = Duration(minutes: 5);

  final LocalAuthentication _auth;

  DateTime? _unlockedUntil;

  /// Whether this device can ask at all.
  ///
  /// Resolved once and cached: there is no web implementation, and on a device
  /// with nothing enrolled the answer cannot change while the app is running
  /// without the person leaving it for Settings — which tears the app down
  /// often enough that a stale `true` is the only wrong answer worth
  /// preventing, and this cannot produce one.
  Future<bool>? _available;

  Future<bool> get isAvailable => _available ??= _resolveAvailability();

  Future<bool> _resolveAvailability() async {
    if (kIsWeb) return false;
    try {
      // `isDeviceSupported` covers hardware and a device passcode;
      // `canCheckBiometrics` covers a sensor with something enrolled on it.
      // Either alone gives the wrong answer on a phone whose sensor nobody has
      // registered a finger with.
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      // A missing platform implementation throws rather than answering. This
      // is a nicety; it must never be the thing that breaks a screen.
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

  /// Forgets any grace period. Called on sign-out: the next person at this
  /// tablet is a different person.
  void relock() => _unlockedUntil = null;

  /// True when the caller may proceed.
  ///
  /// Returns true unprompted when the lock is off, when the device cannot ask,
  /// and while a previous unlock is still inside [grace].
  Future<bool> confirm(String reason) async {
    if (!value) return true;

    final until = _unlockedUntil;
    if (until != null && DateTime.now().isBefore(until)) return true;

    if (!await isAvailable) {
      // Enrolment was removed after the setting was turned on. Refusing here
      // would lock a shop out of its own figures with no way back, so the lock
      // yields — it is a deterrent on an unattended screen, not a vault.
      return true;
    }

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
      return ok;
    } catch (_) {
      // A platform failure is not a refusal. Same reasoning as above: this
      // must not be the thing that stops a shop reading its own takings.
      return true;
    }
  }
}

/// The one instance. Loaded in `main()` alongside the theme, because both are
/// a single key out of shared_preferences and both are needed before the first
/// screen that consults them.
final screenLock = ScreenLock();
