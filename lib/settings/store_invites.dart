import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import '../models/invite.dart';

/// Where a manager issues invite codes.
///
/// A code is six characters, works once, and expires after 30 minutes. Adding
/// three colleagues means issuing three codes — single use is both the safest
/// option and the one that is easiest to explain to an owner who is standing
/// in a kitchen reading a code out loud.
class StoreInvites extends StatefulWidget {
  const StoreInvites({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  final String storeId;

  /// Copied onto every code it issues. The person redeeming it cannot read
  /// `stores/{id}` yet, so the name they are shown has to travel with the code.
  final String storeName;

  @override
  State<StoreInvites> createState() => _StoreInvitesState();
}

class _StoreInvitesState extends State<StoreInvites> {
  /// Redraws the "expires in N minutes" lines. Nothing here is worth a
  /// per-second tick; half a minute keeps them honest without churn.
  Timer? _ticker;

  bool _issuing = false;

  /// The code issued in this session, so it can be shown large and at the top
  /// rather than the person having to find it in the list.
  Invite? _justIssued;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite Codes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _issuing ? null : _issue,
        icon: const Icon(Icons.add),
        label: const Text('New code'),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Invite>>(
          stream: inviteRepository.watchForStore(widget.storeId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _CenteredMessage(
                icon: Icons.lock_outline,
                title: 'Cannot list invite codes',
                detail: '${snapshot.error}',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final invites = snapshot.data!;
            final now = DateTime.now();
            final live = invites.where((i) => !i.isUsed && !i.isExpiredAt(now));
            final spent = invites.where((i) => i.isUsed || i.isExpiredAt(now));

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (_justIssued != null) ...[
                  _IssuedCard(
                    invite: _justIssued!,
                    onCopy: () => _copy(_justIssued!),
                    onDismiss: () => setState(() => _justIssued = null),
                  ),
                  const SizedBox(height: 8),
                ],
                if (invites.isEmpty)
                  const _CenteredMessage(
                    icon: Icons.group_add_outlined,
                    title: 'No codes yet',
                    detail:
                        'Issue one and read it out. Your colleague picks '
                        '"Join an existing store" when they register.',
                  )
                else ...[
                  _SectionHeader('Active (${live.length})'),
                  if (live.isEmpty)
                    const _EmptySection('No code is currently valid.')
                  else
                    ...live.map((i) => _InviteTile(
                          invite: i,
                          now: now,
                          onCopy: () => _copy(i),
                          onRevoke: () => _revoke(i),
                        )),
                  const SizedBox(height: 16),
                  if (spent.isNotEmpty) ...[
                    _SectionHeader('Used and expired'),
                    ...spent.map((i) => _InviteTile(
                          invite: i,
                          now: now,
                          onCopy: null,
                          onRevoke: () => _revoke(i),
                        )),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _issue() async {
    final role = await showDialog<UserRole>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('What may this person do?'),
        children: [
          _RoleOption(
            role: UserRole.staff,
            description: 'Take orders and see the day\'s figures.',
          ),
          _RoleOption(
            role: UserRole.manager,
            description:
                'Everything staff can do, plus edit the menu and prices, '
                'change store settings and issue invite codes.',
          ),
        ],
      ),
    );
    if (role == null || !mounted) return;

    setState(() => _issuing = true);
    try {
      final invite = await inviteRepository.create(
        storeId: widget.storeId,
        storeName: widget.storeName,
        role: role,
        createdBy: authRepository.currentUid ?? '',
      );
      if (mounted) setState(() => _justIssued = invite);
    } on InviteException catch (e) {
      _snack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  Future<void> _revoke(Invite invite) async {
    final label = invite.isUsed || invite.isExpired ? 'Remove' : 'Revoke';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label ${invite.display}?'),
        content: Text(
          invite.isUsed
              ? 'It has already been used, so removing it only tidies this '
                  'list. The colleague who redeemed it keeps their account.'
              : 'Anyone holding this code will no longer be able to join.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await inviteRepository.revoke(invite.code);
      if (_justIssued?.code == invite.code && mounted) {
        setState(() => _justIssued = null);
      }
      _snack('${invite.display} ${label.toLowerCase()}d');
    } on InviteException catch (e) {
      _snack(e.message, isError: true);
    }
  }

  void _copy(Invite invite) {
    Clipboard.setData(ClipboardData(text: invite.code));
    _snack('${invite.display} copied');
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : null,
      duration: Duration(seconds: isError ? 6 : 3),
    ));
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({required this.role, required this.description});

  final UserRole role;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, role),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(role.label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// The freshly issued code, shown big enough to read across a kitchen.
class _IssuedCard extends StatelessWidget {
  const _IssuedCard({
    required this.invite,
    required this.onCopy,
    required this.onDismiss,
  });

  final Invite invite;
  final VoidCallback onCopy;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'New ${invite.role.label.toLowerCase()} code',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close),
                  onPressed: onDismiss,
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              invite.display,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Works once, and only for the next '
              '${_minutesLabel(invite.remainingAt(DateTime.now()))}.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({
    required this.invite,
    required this.now,
    required this.onCopy,
    required this.onRevoke,
  });

  final Invite invite;
  final DateTime now;
  final VoidCallback? onCopy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final spent = invite.isUsed || invite.isExpiredAt(now);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        invite.isUsed
            ? Icons.how_to_reg_outlined
            : (invite.isExpiredAt(now)
                ? Icons.timer_off_outlined
                : Icons.vpn_key_outlined),
      ),
      title: Text(
        invite.display,
        style: TextStyle(
          fontSize: 20,
          letterSpacing: 3,
          fontWeight: FontWeight.w600,
          decoration: spent ? TextDecoration.lineThrough : null,
          color: spent ? Theme.of(context).disabledColor : null,
        ),
      ),
      subtitle: Text(_status(invite, now)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onCopy != null)
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: onCopy,
            ),
          IconButton(
            tooltip: spent ? 'Remove' : 'Revoke',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: onRevoke,
          ),
        ],
      ),
    );
  }

  static String _status(Invite invite, DateTime now) {
    if (invite.isUsed) return 'Used · joins as ${invite.role.label}';
    if (invite.isExpiredAt(now)) return 'Expired · never used';
    return 'Joins as ${invite.role.label} · expires in '
        '${_minutesLabel(invite.remainingAt(now))}';
  }
}

String _minutesLabel(Duration left) {
  final minutes = left.inMinutes;
  if (minutes >= 2) return '$minutes minutes';
  if (minutes == 1) return '1 minute';
  return 'less than a minute';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
