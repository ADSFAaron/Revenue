import 'dart:async';

import 'package:flutter/material.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import '../settings/screen_lock.dart';
import 'entry_button.dart';
import 'entry_ui.dart';

/// Who is at the till, for the indicator on the order screen and for the
/// screen below. Set by `loadSession()`, cleared whenever the session changes.
final currentOperator = ValueNotifier<AppUser?>(null);

/// How long the till may sit untouched before it covers itself. Zero is off,
/// and is the default. Set from the store's settings by `loadSession()`.
final idleTimeout = ValueNotifier<Duration>(Duration.zero);

/// Why the till is covered, or null when it is not.
///
/// The reason is carried rather than inferred because the three cases want
/// different words on the screen: "you left this open" is not the same
/// sentence as "this is where you came in".
enum TillCover {
  /// Nothing was touched for the store's configured interval.
  idle,

  /// The app was opened, or brought back after being away, with the lock on.
  opened,

  /// Somebody tapped the operator indicator to hand the till over.
  handover,
}

final tillLocked = ValueNotifier<TillCover?>(null);

/// How many lines are in the basket on the order screen, or zero when there is
/// no order being rung up.
///
/// The cover reads it to decide whether handing over needs a warning. Handing
/// over always costs the basket — it belongs to the person stepping away, and
/// it would be worse for it to arrive under the next person's name — but a
/// confirmation on every handover would be friction on the exact operation
/// this is all trying to make cheap.
final unsentBasketLines = ValueNotifier<int>(0);

/// Holds the whole signed-in app back until the lock has been passed.
///
/// **Covering was not enough, and this is what replaced it.** The lock used to
/// be a cover painted over a shell that was already mounted: every Firestore
/// stream open, the day's takings fetched, Today and Insights built and laid
/// out underneath. Three things followed from that, and all three were real:
///
///  1. the figures were loaded and rendered before anybody had proved
///     anything, so the lock protected a screenshot rather than the data;
///  2. the cover was a `Stack` child with no position, so it took the size of
///     its own content and the live app carried on below it, tappable;
///  3. anything that cleared the cover — handing over, in particular — was a
///     way in that had never asked.
///
/// A gate cannot have any of those. Nothing under it is built, so nothing
/// under it reads, and the only way past is through [screenLock].
///
/// Keyed on the uid by the caller, so a session ending or changing hands
/// builds a new gate and locks again. That is what closes "switch to a
/// colleague, switch back, and walk in": the second arrival is a new gate with
/// no memory of the first one's unlock, and [ScreenLock.relock] drops the
/// grace period that would otherwise have carried it.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    required this.uid,
    required this.onLocked,
    required this.child,
    super.key,
  });

  /// Whose session this gate stands in front of. Not read — the key is what
  /// does the work — but it is what the key must be built from, and saying so
  /// here is what stops the two drifting apart.
  final String uid;

  /// Told when the gate has decided to hold the app back, so the opening
  /// animation stops waiting for a shell that is not going to be built.
  final VoidCallback onLocked;

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  /// Resolved synchronously so the shell is never built for even one frame on
  /// a device that is meant to be locked. Anything asynchronous here — reading
  /// the setting, asking whether the device can prompt — would be a frame with
  /// the real screen on it, which is the whole defect.
  late bool _unlocked = !screenLock.value;

  bool _handingOver = false;

  @override
  void initState() {
    super.initState();
    if (!_unlocked) screenLock.relock();
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    widget.onLocked();
    if (_handingOver) {
      return const Center(child: CircularProgressIndicator());
    }
    return PopScope(
      // Back must not be a way in. This one is inside the Navigator, so it
      // works; the cover in [IdleLock] sits above the Navigator and cannot use
      // it, which is fine there — back pops a route the cover is already over.
      canPop: false,
      child: TillCoverScreen(
        reason: TillCover.opened,
        // The app was just opened. Asking immediately is what a lock screen
        // does, and it also means the button below is a retry rather than the
        // only way to be asked at all.
        autoPrompt: true,
        onUnlocked: () => setState(() => _unlocked = true),
        // Deliberately not an unlock. The switch has already happened, the uid
        // is about to change, and this gate is about to be replaced by one
        // keyed to the new person — showing the shell in the meantime would
        // mount it under the outgoing operator.
        onHandedOver: () => setState(() => _handingOver = true),
      ),
    );
  }
}

/// Covers the till when it has been left alone, and when somebody is handing
/// it over.
///
/// **It does not sign anybody out**, and that is the design rather than a
/// shortcut. Signing out tears down the whole tree, which takes the basket
/// with it — so a timeout that signed out would lose a half-rung-up order
/// every time somebody turned away to make a coffee. Keeping the session and
/// covering the screen protects the same thing (a counter nobody is standing
/// at) and costs nothing that was on it.
///
/// This is the *mid-shift* half of the lock, and the only half that may cover
/// rather than gate: by the time it runs there is a basket on screen that
/// tearing down would lose. Arriving at the app is the other half and is
/// [AppLockGate]'s, which builds nothing at all.
///
/// Sits above the Navigator, in `MaterialApp.builder`, so it covers pushed
/// routes and dialogs too. A lock with a way around it by opening a screen is
/// not a lock.
class IdleLock extends StatefulWidget {
  const IdleLock({required this.child, super.key});

  final Widget child;

  @override
  State<IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends State<IdleLock> with WidgetsBindingObserver {
  Timer? _timer;

  /// When the app was last put away. Null while it is in front.
  DateTime? _leftAt;

  /// How long the app may be away before coming back counts as arriving.
  /// Shorter than this is a card terminal or a notification, not a handover.
  static const Duration _awayBeforeLocking = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    idleTimeout.addListener(_restart);
    tillLocked.addListener(_onLockChanged);
    // Not only on change. `loadSession()` usually sets the timeout after this
    // is mounted, so the listener covers the ordinary launch — but a hot
    // restart, or any path where a session resolves before this widget is
    // built, would otherwise leave the till with a timeout set and no timer
    // running: configured, and silently doing nothing.
    _restart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    idleTimeout.removeListener(_restart);
    tillLocked.removeListener(_onLockChanged);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    // Leaving the app is the only way to remove a fingerprint or turn off a
    // device passcode, so coming back is the one moment a cached "this device
    // can ask" could be wrong in the direction that matters.
    screenLock.forgetAvailability();

    final leftAt = _leftAt;
    _leftAt = null;
    if (leftAt == null || !screenLock.value) return;
    if (currentOperator.value == null) return;
    if (DateTime.now().difference(leftAt) < _awayBeforeLocking) return;
    tillLocked.value = TillCover.opened;
  }

  void _onLockChanged() {
    if (mounted) setState(() {});
    _restart();
  }

  /// Any touch anywhere is activity. Deliberately the coarsest possible
  /// signal: a till is used by somebody standing over it with one hand, and
  /// anything cleverer would have to be right about every screen in the app.
  void _poke([PointerEvent? _]) {
    if (tillLocked.value != null) return;
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    final timeout = idleTimeout.value;
    if (timeout <= Duration.zero || tillLocked.value != null) return;
    _timer = Timer(timeout, () {
      if (currentOperator.value != null) tillLocked.value = TillCover.idle;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reason = tillLocked.value;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _poke,
      onPointerMove: _poke,
      onPointerSignal: _poke,
      child: Stack(
        children: [
          widget.child,
          if (reason != null)
            // `Positioned.fill`, and the omission of it was the bug in the
            // screenshots. A `Stack` gives an unpositioned child *loose*
            // constraints, so the cover took the height of its own text and
            // the live app carried on below it — visible, scrollable and
            // tappable, with a lock screen sitting on the top third of it.
            Positioned.fill(
              child: TillCoverScreen(
                reason: reason,
                // Coming back to the app is somebody picking the device up, so
                // ask straight away. A timeout is not: the prompt would fire
                // at an unattended counter, go unanswered, and be a refusal by
                // the time anybody returned.
                autoPrompt: reason == TillCover.opened,
                onUnlocked: () => tillLocked.value = null,
                onHandedOver: () => tillLocked.value = null,
              ),
            ),
        ],
      ),
    );
  }
}

/// What is on screen while the till is covered or held back.
///
/// Opaque, and it says whose session is underneath rather than showing it —
/// the point of covering a counter is that the takings on the screen behind
/// are not readable from the other side of it.
class TillCoverScreen extends StatefulWidget {
  const TillCoverScreen({
    required this.reason,
    required this.onUnlocked,
    required this.onHandedOver,
    this.autoPrompt = false,
    super.key,
  });

  final TillCover reason;

  /// Whether to raise the device prompt as soon as this is shown.
  final bool autoPrompt;

  /// The lock was passed. Whoever put this on screen decides what that means.
  final VoidCallback onUnlocked;

  /// The till is changing hands; the session is already switching underneath.
  final VoidCallback onHandedOver;

  @override
  State<TillCoverScreen> createState() => _TillCoverScreenState();
}

class _TillCoverScreenState extends State<TillCoverScreen> {
  bool _busy = false;

  /// Set while asking whether an order on the till is worth losing.
  ///
  /// Asked inline rather than with `showDialog`, and that is not a style
  /// choice: in [IdleLock] this is mounted from `MaterialApp.builder`, which
  /// is *above* the Navigator, so there is no NavigatorState over it to put a
  /// route on — `showDialog` from there throws. Being above the Navigator is
  /// the whole reason the cover works over pushed routes and dialogs, so the
  /// cover is the thing that has to adapt.
  bool _confirming = false;

  /// True once a check came back [LockCheck.unavailable]: the lock is on and
  /// this device cannot ask any more.
  ///
  /// This is the state the old code could not represent, and so let through.
  /// It is not a reason to open the app — somebody who removed the device's
  /// screen lock has not proved anything — and it is not a reason to brick the
  /// till either. Both honest ways out are offered instead, and they are
  /// offered *here*, once, rather than silently at every screen.
  bool _cannotAsk = false;

  /// Who the pending handover is to. Null means somebody this device has
  /// never held a session for, who signs in on the next screen.
  DeviceAccount? _target;

  @override
  void initState() {
    super.initState();
    if (widget.autoPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = _identity();

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: EntryBody(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
          children: [
            const EntryHeader(),
            const SizedBox(height: 40),
            if (who != null) ...[
              Center(
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                  child: Text(who.initials, style: theme.textTheme.titleLarge),
                ),
              ),
              const SizedBox(height: 16),
              StepTitle(who.label),
              const SizedBox(height: 8),
              StepSubtitle(_subtitle),
            ] else
              StepTitle(_subtitle),
            const SizedBox(height: 36),
            if (_confirming)
              _buildConfirm(context)
            else if (_cannotAsk)
              _buildCannotAsk(context)
            else ...[
              EntryButton(
                label: 'Carry on',
                busy: _busy,
                onPressed: _busy ? null : _unlock,
              ),
              const SizedBox(height: 28),
              _HandOverRow(
                exclude: who?.uid,
                enabled: !_busy,
                onPerson: (account) => _requestHandover(account),
                onSomebodyNew: () => _requestHandover(null),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _subtitle => _cannotAsk
      ? 'The lock is on, and this device can no longer ask.'
      : switch (widget.reason) {
          TillCover.idle => 'The till was left alone.',
          TillCover.opened => 'Still signed in. Unlock to carry on.',
          TillCover.handover => 'Carrying on, or handing over?',
        };

  /// Whose session this is, without reading a thing from the database.
  ///
  /// [currentOperator] once a session has resolved; otherwise the signed-in
  /// account itself, which Firebase holds locally. At the gate the first is
  /// deliberately null — nothing has loaded, which is the point — and the
  /// second is what puts a name on the screen without fetching one.
  _CoverIdentity? _identity() {
    final operator = currentOperator.value;
    if (operator != null) {
      return _CoverIdentity(
        uid: operator.uid,
        label: operator.displayLabel,
        initials: operator.initials,
      );
    }
    // Guarded, because this is the one widget that must never be the thing
    // that crashes: `currentSignIn()` reads through the active session app,
    // and asking for one before a slot is open throws. A cover with no name on
    // it is a small loss; a cover that throws is an unlockable device.
    final SignInResult? account;
    try {
      account = authRepository.currentSignIn();
    } catch (_) {
      return null;
    }
    if (account == null) return null;
    final user = AppUser(
      uid: account.uid,
      email: account.email,
      displayName: account.displayName,
      storeId: '',
    );
    return _CoverIdentity(
      uid: user.uid,
      label: user.displayLabel,
      initials: user.initials,
    );
  }

  Future<void> _unlock() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await screenLock.check(
        'Unlock the till',
        // The way in never honours the grace period. Handing the till to a
        // colleague and taking it straight back used to land inside the first
        // person's five minutes and walk in unasked.
        allowGrace: false,
      );
      if (!mounted) return;
      switch (result) {
        case LockCheck.passed:
          widget.onUnlocked();
        case LockCheck.refused:
          // Cancelled, or the wrong finger. The cover stays exactly as it is;
          // the button is the retry.
          break;
        case LockCheck.unavailable:
          setState(() => _cannotAsk = true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Starts a handover, asking first only when there is something to lose.
  void _requestHandover(DeviceAccount? target) {
    if (unsentBasketLines.value == 0) {
      _handOver(target);
      return;
    }
    setState(() {
      _confirming = true;
      _target = target;
    });
  }

  /// Hands the till to a named colleague.
  ///
  /// When this device is already holding their session the switch is local: no
  /// round trip, no passkey, and it works with the wifi off. When it is not,
  /// the current operator is *parked* rather than signed out — they stay
  /// signed in on their own slot, so handing it back later is local too — and
  /// the entry screen takes it from there.
  ///
  /// Either way this is **not** an unlock, and it used to be treated as one.
  /// The incoming session arrives at its own gate; nothing here decides that
  /// somebody has proved anything.
  Future<void> _handOver(DeviceAccount? target) async {
    setState(() {
      _busy = true;
      _confirming = false;
    });
    try {
      if (target != null && await sessionApps.switchTo(target.uid)) {
        widget.onHandedOver();
        return;
      }
      await addAnotherOperator();
      widget.onHandedOver();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The question, on the cover itself.
  Widget _buildConfirm(BuildContext context) {
    final lines = unsentBasketLines.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepSubtitle(
          '$lines ${lines == 1 ? 'dish has' : 'dishes have'} been rung up and '
          'not sent. Handing over now loses them — an order half rung up by '
          'one person should not arrive under somebody else\'s name.\n\n'
          'Orders already sent are not affected, including any still waiting '
          'for a connection.',
        ),
        const SizedBox(height: 28),
        EntryButton(
          label: 'Go back',
          onPressed: () => setState(() => _confirming = false),
        ),
        const SizedBox(height: 16),
        EntryButton.outlined(
          label: 'Hand over anyway',
          onPressed: _busy ? null : () => _handOver(_target),
        ),
      ],
    );
  }

  /// The lock is on and the device cannot honour it.
  ///
  /// Signing in again is the primary way out because it is the one that
  /// actually proves something: a passkey or a password is authentication,
  /// which is what is missing here. Turning the lock off is offered second and
  /// says plainly what it gives up — it is not a bypass, since removing this
  /// device's screen lock already took knowing its PIN.
  Widget _buildCannotAsk(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepSubtitle(
          'This device has no fingerprint, face, PIN or pattern set up any '
          'more, so there is nothing left to ask for. A fingerprint here only '
          'ever showed somebody was holding the device — signing in is what '
          'shows who they are, so that is the way back in.',
        ),
        const SizedBox(height: 28),
        EntryButton(
          label: 'Sign in again',
          busy: _busy,
          onPressed: _busy ? null : _signInAgain,
        ),
        const SizedBox(height: 16),
        EntryButton.outlined(
          label: 'Turn the lock off',
          onPressed: _busy ? null : _turnLockOff,
        ),
        const SizedBox(height: 20),
        const StepNote(
          'Turning it off leaves this device open at whatever screen it was '
          'left on. Set the device\'s own screen lock up again to put it back.',
        ),
      ],
    );
  }

  Future<void> _signInAgain() async {
    setState(() => _busy = true);
    try {
      await signOutOperator();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnLockOff() async {
    await screenLock.setEnabled(false);
    if (mounted) widget.onUnlocked();
  }
}

/// Who the cover says is underneath it.
class _CoverIdentity {
  const _CoverIdentity({
    required this.uid,
    required this.label,
    required this.initials,
  });

  final String uid;
  final String label;
  final String initials;
}

/// Who else this till can be handed to.
///
/// The people this device is already holding a session for come first and are
/// marked, because tapping one of them is instant and works with no
/// connection — that is the difference the slots exist to make, and it is
/// worth being able to see before you tap.
class _HandOverRow extends StatelessWidget {
  const _HandOverRow({
    required this.exclude,
    required this.enabled,
    required this.onPerson,
    required this.onSomebodyNew,
  });

  final String? exclude;
  final bool enabled;
  final ValueChanged<DeviceAccount> onPerson;
  final VoidCallback onSomebodyNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others = [
      for (final account in deviceAccounts.accounts)
        if (account.uid != exclude) account,
    ]..sort((a, b) {
        final aLive = sessionApps.holdsSessionFor(a.uid) ? 0 : 1;
        final bLive = sessionApps.holdsSessionFor(b.uid) ? 0 : 1;
        return aLive.compareTo(bLive);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hand over to',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final account in others)
              ActionChip(
                avatar: sessionApps.holdsSessionFor(account.uid)
                    ? Icon(Icons.bolt_rounded,
                        size: 18, color: theme.colorScheme.primary)
                    : const Icon(Icons.person_outline, size: 18),
                label: Text(account.label),
                tooltip: sessionApps.holdsSessionFor(account.uid)
                    ? 'Still signed in on this device — no connection needed'
                    : 'Signs in on the next screen',
                onPressed: enabled ? () => onPerson(account) : null,
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Somebody else'),
              onPressed: enabled ? onSomebodyNew : null,
            ),
          ],
        ),
        const SizedBox(height: 20),
        const StepNote(
          'Carrying on keeps whatever is in the basket. Handing over does '
          'not — an order half rung up by one person should not arrive under '
          'somebody else\'s name.',
        ),
      ],
    );
  }
}

/// The standing "who is at this till" indicator.
///
/// Most mis-attribution is inattention rather than intent — somebody walks up
/// to a till their colleague left open and rings an order up under that name.
/// Saying whose name it will be, on the screen where it is about to happen, is
/// the cheapest thing that addresses that, and tapping it is the way to fix it
/// in the same breath.
class OperatorChip extends StatelessWidget {
  const OperatorChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: currentOperator,
      builder: (context, operator, _) {
        if (operator == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ActionChip(
            avatar: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              child: Text(
                operator.initials,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
            label: Text(operator.displayLabel),
            tooltip: 'Ringing up as ${operator.displayLabel} — tap to hand over',
            onPressed: () => tillLocked.value = TillCover.handover,
          ),
        );
      },
    );
  }
}
