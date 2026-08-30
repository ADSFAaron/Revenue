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
                          return _StaffTile(
                            user: user,
                            me: me,
                            onChangeRole: _mayChangeRoleOf(me, user)
                                ? () => _changeRole(context, user)
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

  /// Managers may change a colleague's role, but never their own — that is how
  /// somebody would promote themselves — and never the owner's. A store has
  /// exactly one owner and it is whoever opened it.
  static bool _mayChangeRoleOf(AppUser? me, AppUser target) =>
      me != null &&
      me.role.canManage &&
      me.uid != target.uid &&
      target.role != UserRole.owner;

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
  });

  final AppUser user;
  final AppUser? me;
  final VoidCallback? onChangeRole;

  @override
  Widget build(BuildContext context) {
    final isMe = me?.uid == user.uid;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: ListTile(
        title: Text(
          user.displayName.isEmpty ? user.email : user.displayName,
        ),
        subtitle: Text(
          '${user.email}\n${user.role.label}${isMe ? ' · you' : ''}',
        ),
        isThreeLine: true,
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
          child: Text(user.initials),
        ),
        trailing: onChangeRole == null
            ? null
            : IconButton(
                tooltip: 'Change role',
                icon: const Icon(Icons.manage_accounts_outlined),
                onPressed: onChangeRole,
              ),
        onTap: onChangeRole,
      ),
    );
  }
}
