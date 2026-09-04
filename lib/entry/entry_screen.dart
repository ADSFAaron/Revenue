import 'package:flutter/material.dart';

import '../database/repositories.dart';
import 'choose_path.dart';
import 'entry_button.dart';
import 'entry_ui.dart';
import 'sign_in.dart';

/// The first screen of the app when nobody is signed in.
///
/// It is a list of the people who use this till, not a login form. That
/// inversion is the whole point. On a shared counter tablet the thing that
/// decides whether orders are attributed correctly is not how strong the
/// authentication is — it is whether switching is cheaper than sharing. A shop
/// that has to type an address and a password to change hands will leave one
/// account signed in all day, and then `createdBy` is a lie on every order
/// after the first shift. Tapping your own name and touching the sensor is
/// about two seconds, which is cheap enough to actually happen.
///
/// See docs/auth-and-operator-plan.md §3.1. Signing in with an address is
/// still here, one tap away, because a device has to have a first person on it
/// and because people do lose their phones.
class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  /// Resolved once. Whether this device can do passkeys cannot change while
  /// the screen is open, and asking on every rebuild would be wasteful.
  late final Future<bool> _passkeysSupported = passkeyRepository.isSupported();

  /// Which person's sign-in is running, so their tile alone shows it.
  String? _busyUid;

  @override
  void initState() {
    super.initState();
    deviceAccounts.addListener(_onRoster);
    if (!deviceAccounts.isLoaded) deviceAccounts.load();
  }

  @override
  void dispose() {
    deviceAccounts.removeListener(_onRoster);
    super.dispose();
  }

  void _onRoster() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accounts = deviceAccounts.accounts;

    return Scaffold(
      body: SafeArea(
        child: EntryBody(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
          children: accounts.isEmpty
              ? _firstRun(context)
              : _roster(context, accounts),
        ),
      ),
    );
  }

  /// A device nobody has signed in on yet. There is no list to show, so this
  /// says what the app is and offers the two things a newcomer can do.
  List<Widget> _firstRun(BuildContext context) => [
        const SizedBox(height: 24),
        const EntryHeader(tagline: 'What the till took, and what it kept.'),
        const SizedBox(height: 48),
        EntryButton(
          label: 'Sign in',
          onPressed: () => _push(const SignInScreen()),
        ),
        const SizedBox(height: 16),
        EntryButton.outlined(
          label: 'Get started',
          onPressed: () => _push(const ChoosePathScreen()),
        ),
        const SizedBox(height: 24),
        const StepNote(
          'Opening a shop, or joining one with an invite code.',
        ),
      ];

  List<Widget> _roster(BuildContext context, List<DeviceAccount> accounts) => [
        const EntryHeader(),
        const SizedBox(height: 32),
        const StepTitle('Who’s at the till?'),
        const SizedBox(height: 28),
        // Wrap rather than a grid: the number of people at a shop is small and
        // unknown, and a grid with a fixed column count is wrong at both ends
        // of that range.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final account in accounts)
              _PersonTile(
                account: account,
                live: sessionApps.holdsSessionFor(account.uid),
                busy: _busyUid == account.uid,
                enabled: _busyUid == null,
                onTap: () => _signInAs(account),
                onForget: () => _forget(account),
              ),
            _OtherAccountTile(
              enabled: _busyUid == null,
              onTap: () => _push(const SignInScreen()),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const StepNote(
          'Tap and hold a name to take it off this device. That does not '
          'touch the account — removing somebody from the shop is done in '
          'Store → Staff.',
        ),
      ];

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  /// Signs this person in the fastest way this device can, and falls back to
  /// the form rather than to a dead end.
  Future<void> _signInAs(DeviceAccount account) async {
    // A session this device is still holding needs nothing at all: no round
    // trip, no passkey, and it works with the wifi off — which is the case a
    // counter tablet is most likely to be in when it changes hands.
    setState(() => _busyUid = account.uid);
    try {
      if (await sessionApps.switchTo(account.uid)) return;
    } finally {
      if (mounted) setState(() => _busyUid = null);
    }

    final canUsePasskey =
        account.passkeyIds.isNotEmpty && await _passkeysSupported;
    if (!mounted) return;

    if (!canUsePasskey) {
      // No passkey of theirs on this device, so there is nothing to be fast
      // with. Their address is already known, which is the half of the form
      // worth saving them.
      _push(SignInScreen(email: account.email));
      return;
    }

    setState(() => _busyUid = account.uid);
    try {
      // Narrowed to their own credentials, so the authenticator asks for a
      // fingerprint instead of asking them to pick themselves out of a list of
      // colleagues they have just picked themselves out of.
      await passkeyRepository.signIn(credentialIds: account.passkeyIds);
      // Nothing to navigate to: the root is watching auth state and replaces
      // this screen the moment the session lands.
    } on PasskeyException catch (e) {
      if (!mounted) return;
      switch (e.failure) {
        case PasskeyFailure.cancelled:
          break; // A decision, not a failure.
        case PasskeyFailure.noCredentials:
          // The passkey was deleted from the device or from the account since
          // it was last used, so what this device believed is out of date.
          await deviceAccounts.forgetPasskeys(account.uid);
          if (mounted) _push(SignInScreen(email: account.email));
        default:
          showEntryError(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busyUid = null);
    }
  }

  Future<void> _forget(DeviceAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Take ${account.label} off this device?'),
        content: const Text(
          'Their name stops appearing here. The account itself is untouched — '
          'they can sign in again on this or any other device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Take off'),
          ),
        ],
      ),
    );
    if (confirmed == true) await deviceAccounts.forget(account.uid);
  }
}

/// One person on this device.
class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.account,
    required this.live,
    required this.busy,
    required this.enabled,
    required this.onTap,
    required this.onForget,
  });

  final DeviceAccount account;

  /// This device is still holding their session, so tapping is instant and
  /// needs no connection.
  final bool live;

  final bool busy;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _EntryTile(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onForget : null,
      semanticLabel: 'Sign in as ${account.label}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 56,
            width: 56,
            child: busy
                ? const Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : CircleAvatar(
                    backgroundColor: scheme.secondaryContainer,
                    foregroundColor: scheme.onSecondaryContainer,
                    child: Text(
                      account.initials,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            account.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (live) ...[
            const SizedBox(height: 4),
            Icon(Icons.bolt_rounded, size: 16, color: scheme.primary),
          ] else if (account.passkeyIds.isNotEmpty) ...[
            const SizedBox(height: 4),
            Icon(Icons.fingerprint, size: 16, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );
  }
}

class _OtherAccountTile extends StatelessWidget {
  const _OtherAccountTile({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _EntryTile(
      onTap: enabled ? onTap : null,
      semanticLabel: 'Sign in with another account',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 56,
            width: 56,
            child: CircleAvatar(
              backgroundColor: scheme.surfaceContainerHighest,
              foregroundColor: scheme.onSurfaceVariant,
              child: const Icon(Icons.add),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Another\naccount',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// The shared shape. 132 square is comfortably past the 48pt minimum in both
/// directions — this is the control somebody uses with one hand while holding
/// a card machine in the other.
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: 132,
        height: 148,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ExcludeSemantics(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
