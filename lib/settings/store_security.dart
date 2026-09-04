import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../widgets/feedback.dart';
import '../widgets/page_body.dart';
import '../widgets/setting_tile.dart';
import 'screen_lock.dart';
import 'store_settings_audit_log.dart';
import 'user_passkeys.dart';

/// What is protecting this shop's figures, in one place.
///
/// The reason this screen exists is a question the owner asked in a
/// particular form — "can we add two-factor authentication, because shops care
/// about commercial confidentiality". Two-factor was the wrong answer to a
/// right question. Ranked by how a shop's books actually leak, the paths are:
///
///   1. a till left signed in on a counter, in reach of anybody who walks
///      behind it — by far the most likely, and the one TOTP does nothing
///      about;
///   2. staff with more read access than the job needs;
///   3. a stolen password — already better answered by passkeys than by
///      password-plus-code;
///   4. something reaching the database that is not this app at all.
///
/// All four are addressed, and none of it was visible to the person who asked.
/// A security posture nobody can see is one a shop cannot weigh, so this
/// screen says what is in place and offers the one control that was missing —
/// the lock for (1).
class StoreSecurity extends StatefulWidget {
  const StoreSecurity({required this.storeId, required this.role, super.key});

  final String storeId;
  final UserRole role;

  @override
  State<StoreSecurity> createState() => _StoreSecurityState();
}

class _StoreSecurityState extends State<StoreSecurity> {
  late final Future<bool> _lockAvailable = screenLock.isAvailable;

  bool get _canManage => widget.role.canManage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: SafeArea(
        child: ReadingWidth(
          builder: (context, insets) => ListView(
            padding: insets + const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const SettingSection('This device', first: true),
              _buildLockTile(),
              const SettingSection('This account'),
              SettingTile.page(
                // Not a fingerprint icon, and not fingerprint wording. These
                // two rows both begin with a fingertip and answer opposite
                // questions, which is exactly why they were being read as the
                // same feature: the lock above asks *somebody is holding this
                // device*, and says nothing about who; a passkey proves *who*,
                // to the server, and is what creates a session at all.
                icon: Icons.key_outlined,
                title: 'Passkeys',
                subtitle: 'Sign in as you, with no password to steal',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UserPasskeys()),
                ),
              ),
              const SettingSection('This shop'),
              SettingTile.page(
                icon: Icons.fact_check_outlined,
                title: 'Change history',
                subtitle: 'Who voided, edited or repriced, and when',
                locked: !_canManage,
                onTap: _openAuditLog,
              ),
              const SizedBox(height: 24),
              _buildPosture(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLockTile() {
    return FutureBuilder<bool>(
      future: _lockAvailable,
      builder: (context, snapshot) {
        final available = snapshot.data ?? false;
        return ValueListenableBuilder<bool>(
          valueListenable: screenLock,
          builder: (context, enabled, _) => SettingTile.inline(
            icon: Icons.lock_outline,
            title: 'Lock the figures',
            subtitle: available
                ? 'This device\'s own fingerprint, face or PIN, asked for '
                    'when the app opens and before the figures, the staff '
                    'list and the change history'
                // Said plainly rather than by disabling a switch with no
                // explanation — "why is this greyed out" is the question a
                // greyed-out switch always produces.
                : 'This device has no fingerprint, face, PIN or pattern set '
                    'up, so there is nothing to ask for',
            trailing: Switch(
              value: enabled && available,
              onChanged: available ? _setLock : null,
            ),
            onTap: available ? () => _setLock(!enabled) : null,
          ),
        );
      },
    );
  }

  Future<void> _setLock(bool enabled) async {
    // Turning it *off* is the direction that needs proving. Anybody can switch
    // a lock on; only somebody who can already get past it should be able to
    // take it away, or the lock is one tap deep.
    if (!enabled && !await screenLock.confirm('Unlock to turn the lock off')) {
      return;
    }
    await screenLock.setEnabled(enabled);
    if (!mounted) return;
    showInfo(
      context,
      enabled ? 'The figures are locked on this device' : 'Lock turned off',
    );
  }

  Future<void> _openAuditLog() async {
    if (!await screenLock.confirm('Unlock to open the change history')) return;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StoreAuditLog(widget.storeId)),
    );
  }

  /// The part that is already true and was invisible.
  ///
  /// Every line here describes something that ships today. Nothing on this
  /// screen may claim a protection the code does not implement — a security
  /// page that overstates is worse than none, because it is what somebody
  /// decides against a real threat with.
  Widget _buildPosture(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What already protects this shop',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const _Point(
              icon: Icons.phone_iphone_rounded,
              title: 'A session outlives being closed',
              body: 'Signing in once keeps you signed in, which is right for '
                  'a till and wrong for a phone in a bag — so with the lock '
                  'on, opening the app asks before anything is loaded or '
                  'shown, not after.',
            ),
            const _Point(
              icon: Icons.key_outlined,
              title: 'Passkeys instead of a code',
              body: 'A passkey cannot be phished, reused or read off a note '
                  'by the till. That is a stronger answer to a stolen '
                  'password than a password plus a six-digit code.',
            ),
            const _Point(
              icon: Icons.groups_outlined,
              title: 'Staff see what the job needs',
              body: 'Taking orders does not carry the right to change the '
                  'menu, read the change history, or edit an order from last '
                  'week. Removing somebody takes their access away on every '
                  'device at once.',
            ),
            const _Point(
              icon: Icons.history_toggle_off,
              title: 'Voids and edits are on record',
              body: 'Every void, order edit, discount and price change is '
                  'written with who did it and when, in the same breath as '
                  'the change itself. Nobody can edit or delete an entry, '
                  'including the owner.',
            ),
            const _Point(
              icon: Icons.verified_user_outlined,
              title: 'Only this app can reach the data',
              body: 'Requests carry an attestation that they came from a '
                  'genuine build. The rules are enforced by the database, not '
                  'by the screens — hiding a button is not a permission.',
            ),
            const _Point(
              icon: Icons.delete_outline,
              title: 'Leaving takes the data with it',
              body: 'Deleting the owner\'s account deletes the shop: its '
                  'orders, menu, staff records and sign-ins. Nothing is kept '
                  'back.',
              last: true,
            ),
            const SizedBox(height: 8),
            Text(
              'A fingerprint on a shared tablet says the till is not '
              'unattended. It does not say who is holding it — no phone can '
              'tell one enrolled finger from another — so orders are '
              'attributed by who is signed in, never by the sensor.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
