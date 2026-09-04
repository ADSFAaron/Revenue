import 'package:flutter/material.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import 'store_invites.dart';
import '../widgets/feedback.dart';
import '../widgets/page_body.dart';
import '../widgets/empty_state.dart';

/// The store's staff, read by reverse lookup on `users.storeId`.
///
/// Also where a manager changes what a colleague is allowed to do. Promoting
/// somebody used to be impossible: the rules only ever let a user write their
/// own document, so nobody could raise anybody else.
class StoreStaff extends StatelessWidget {
  const StoreStaff(this.storeId, {super.key, this.storeName = ''});

  final String storeId;

  /// Needed by the invite screen — every code carries the store's name,
  /// because whoever redeems it cannot read the store document yet.
  final String storeName;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: userRepository.watchCurrent(),
      builder: (context, meSnapshot) {
        final me = meSnapshot.data;
        final canManage = me?.role.canManage ?? false;

        return Scaffold(
          appBar: AppBar(title: const Text('Store Staff')),
          floatingActionButton: canManage
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StoreInvites(
                        storeId: storeId,
                        storeName: storeName,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Invite'),
                )
              : null,
          // Without knowing who is looking, this page cannot say what they
          // are allowed to do: `me` falling to null took the Invite button and
          // every role control away and said nothing, so a manager hitting a
          // transient error on their own document looked like a manager who
          // had been demoted. The inner stream reports its own failure; this
          // one had nowhere to report to.
          body: meSnapshot.hasError
              ? ErrorView(meSnapshot.error!)
              : StreamBuilder<List<AppUser>>(
                  stream: userRepository.watchStaff(storeId),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ErrorView(snapshot.error!);
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final staff = snapshot.data!;
                    if (staff.isEmpty) {
                      return EmptyState(
                        icon: Icons.groups_outlined,
                        title: 'Nobody on the team yet',
                        body: canManage
                            ? 'Issue an invite code and whoever redeems it joins '
                                'this store.'
                            : 'Ask the owner to invite your colleagues.',
                      );
                    }

                    return ReadingWidth(
                      builder: (context, insets) => ListView.builder(
                        padding:
                            insets + const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        itemCount: staff.length,
                        itemBuilder: (context, index) {
                          final user = staff[index];
                          final mayEdit = _mayEdit(me, user);
                          return _StaffTile(
                            user: user,
                            me: me,
                            onChangeRole: mayEdit
                                ? () => _changeRole(context, user)
                                : null,
                            onSetActive: mayEdit
                                ? () => _setActive(context, user)
                                : null,
                          );
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  /// Managers may change a colleague's role and whether they still work here,
  /// but never their own — that is how somebody would promote themselves, and
  /// how a shop locks its last manager out — and never the owner's. A store
  /// has exactly one owner and it is whoever opened it.
  ///
  /// The same line is drawn in firestore.rules; this only decides whether the
  /// control is offered.
  static bool _mayEdit(AppUser? me, AppUser target) =>
      me != null &&
      me.role.canManage &&
      me.uid != target.uid &&
      target.role != UserRole.owner;

  /// Removes somebody from the store, or puts them back.
  ///
  /// Worth a confirmation in one direction only: restoring is undoable by the
  /// same tap, removing takes somebody's till away mid-shift.
  Future<void> _setActive(BuildContext context, AppUser user) async {
    final name = user.displayName.isEmpty ? user.email : user.displayName;

    if (user.active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove $name from this store?'),
          content: const Text(
            'They lose access to the menu, the orders and the takings on '
            'every device, straight away.\n\n'
            'The orders they rang up stay — those are the shop\'s books. You '
            'can put them back on this screen if they return.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await userRepository.setActive(user.uid, !user.active);
      if (context.mounted) {
        showInfo(
          context,
          user.active
              ? '$name no longer has access to this store'
              : '$name is back on the team',
        );
      }
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  Future<void> _changeRole(BuildContext context, AppUser user) async {
    final name = user.displayName.isEmpty ? user.email : user.displayName;
    final chosen = await showDialog<UserRole>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('What may $name do?'),
        children: [
          for (final role in const [UserRole.staff, UserRole.manager])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, role),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      user.role == role
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(role.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            role == UserRole.manager
                                ? 'Edit the menu and prices, change store '
                                    'settings, issue invite codes.'
                                : 'Take orders and see the day\'s figures.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (chosen == null || chosen == user.role) return;

    try {
      await userRepository.updateRole(user.uid, chosen);
      // This widget is stateless, so the guard is on the context itself.
      if (context.mounted) {
        showInfo(context, '$name is now ${chosen.label.toLowerCase()}');
      }
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({
    required this.user,
    required this.me,
    required this.onChangeRole,
    required this.onSetActive,
  });

  final AppUser user;
  final AppUser? me;
  final VoidCallback? onChangeRole;
  final VoidCallback? onSetActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMe = me?.uid == user.uid;
    // A removed member stays on the list — somebody has to be able to put them
    // back — so the tile has to say which of the two states it is showing, and
    // colour alone would not (it would also be the only thing distinguishing
    // them for anybody who cannot see it).
    final removed = !user.active;
    final muted = removed ? scheme.onSurfaceVariant : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: ListTile(
        title: Text(
          user.displayName.isEmpty ? user.email : user.displayName,
          style: TextStyle(color: muted),
        ),
        subtitle: Text(
          '${user.email}\n'
          '${removed ? 'No longer works here' : user.role.label}'
          '${isMe ? ' · you' : ''}',
          style: TextStyle(color: muted),
        ),
        isThreeLine: true,
        leading: CircleAvatar(
          backgroundColor: removed
              ? scheme.surfaceContainerHighest
              : scheme.secondaryContainer,
          foregroundColor:
              removed ? scheme.onSurfaceVariant : scheme.onSecondaryContainer,
          child: Text(user.initials),
        ),
        trailing: onSetActive == null && onChangeRole == null
            ? null
            : PopupMenuButton<_StaffAction>(
                tooltip: 'Manage this person',
                icon: const Icon(Icons.more_vert),
                onSelected: (action) => switch (action) {
                  _StaffAction.changeRole => onChangeRole?.call(),
                  _StaffAction.setActive => onSetActive?.call(),
                },
                itemBuilder: (context) => [
                  if (onChangeRole != null && !removed)
                    const PopupMenuItem(
                      value: _StaffAction.changeRole,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.manage_accounts_outlined),
                        title: Text('Change role'),
                      ),
                    ),
                  if (onSetActive != null)
                    PopupMenuItem(
                      value: _StaffAction.setActive,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          removed
                              ? Icons.person_add_alt
                              : Icons.person_remove_outlined,
                          color: removed ? null : scheme.error,
                        ),
                        title: Text(
                          removed ? 'Put back on the team' : 'Remove from store',
                          style: removed ? null : TextStyle(color: scheme.error),
                        ),
                      ),
                    ),
                ],
              ),
        onTap: removed ? onSetActive : onChangeRole,
      ),
    );
  }
}

enum _StaffAction { changeRole, setActive }
