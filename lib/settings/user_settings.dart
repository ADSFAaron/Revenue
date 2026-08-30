import 'package:flutter/material.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import '../widgets/feedback.dart';
import 'change_password.dart';
import 'user_passkeys.dart';
import '../widgets/page_body.dart';
import '../widgets/empty_state.dart';

/// The signed-in user's own profile.
///
/// This used to read the whole `users` collection and display whichever
/// document came back first, which showed a stranger's name as often as not.
class UserSettings extends StatefulWidget {
  const UserSettings({super.key});

  @override
  State<UserSettings> createState() => _UserSettingsState();
}

class _UserSettingsState extends State<UserSettings> {
  /// Stateful purely so this has an owner.
  ///
  /// It used to be created inside [_editDisplayName] and disposed straight
  /// after the await, which throws "A TextEditingController was used after
  /// being disposed": `showDialog`'s future completes when the route is
  /// popped, which is the *start* of the exit transition, and the TextField is
  /// still mounted and still reading the controller. Cancel crashed every
  /// time.
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Settings')),
      body: SafeArea(
        child: StreamBuilder<AppUser?>(
          stream: userRepository.watchCurrent(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorView(snapshot.error!);
            }
            if (!snapshot.hasData &&
                snapshot.connectionState != ConnectionState.active) {
              return const Center(child: CircularProgressIndicator());
            }

            final user = snapshot.data;
            if (user == null) {
              // Signed in, but the profile document is not there. Almost
              // always mid-registration; occasionally an account whose
              // provisioning failed.
              return const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'No profile for this account',
                body: 'Sign out and back in. If it keeps happening, the '
                    'account was not finished being set up.',
              );
            }
            return _buildUserSettings(context, user);
          },
        ),
      ),
    );
  }

  Widget _buildUserSettings(BuildContext context, AppUser user) {
    return ReadingWidth(
      builder: (context, insets) => ListView(
        padding: insets,
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('User Name'),
            subtitle:
                Text(user.displayName.isEmpty ? 'No Name' : user.displayName),
            trailing: const Icon(Icons.keyboard_arrow_right_outlined),
            onTap: () => _editDisplayName(context, user),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Email'),
            subtitle: Text(user.email.isEmpty ? 'No Email' : user.email),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Role'),
            subtitle: Text(user.role.label),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change Password'),
            trailing: const Icon(Icons.keyboard_arrow_right_outlined),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ChangePassword()),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Passkeys'),
            subtitle:
                const Text('Sign in with a fingerprint, face or screen lock'),
            trailing: const Icon(Icons.keyboard_arrow_right_outlined),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UserPasskeys()),
            ),
          ),
          const Divider(height: 24),
          // App Store guideline 5.1.1(v): an app that lets somebody create an
          // account has to let them delete it, from inside the app, along with
          // their data. It has to be easy to find, so it sits on the profile
          // screen rather than behind a support flow.
          ListTile(
            leading: Icon(Icons.person_remove_outlined,
                color: Theme.of(context).colorScheme.error),
            title: Text(
              'Delete account',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: Text(user.role == UserRole.owner
                ? 'Closes the store and erases everything in it'
                : 'Removes you from this store and deletes your login'),
            onTap: () => _deleteAccount(user),
          ),
        ],
      ),
    );
  }

  /// Two steps, because the owner's version is not reversible and is not only
  /// about them: it takes the shop's entire history and every colleague's
  /// login with it.
  Future<void> _deleteAccount(AppUser user) async {
    final owner = user.role == UserRole.owner;
    final store = owner ? await storeRepository.fetch(user.storeId) : null;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Text(
          owner
              ? 'You own ${store?.name ?? 'this store'}. Deleting your account '
                  'closes it: every order, every day\'s takings, the menu, and '
                  'your colleagues\' logins all go with it. There is no undo '
                  'and no export afterwards.'
              : 'Your login and your place on this store are deleted. The '
                  'orders you rang up stay on the store\'s books.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep my account'),
          ),
          DestructiveButton(
            label: 'Continue',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    String? typedName;
    if (owner) {
      // Typing the shop's name is the only thing between a mis-tap and a
      // business's records.
      typedName = await _askForStoreName(store?.name ?? '');
      if (typedName == null || !mounted) return;
    }

    try {
      await authRepository.deleteAccount(storeName: typedName);
      // The auth listener at the root notices the account is gone and returns
      // to the welcome screen on its own.
    } on AuthException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<String?> _askForStoreName(String storeName) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Type the store name to confirm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter “$storeName” exactly.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Store name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            label: 'Delete everything',
            onPressed: () => Navigator.pop(context, controller.text),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _editDisplayName(BuildContext context, AppUser user) async {
    _nameController.text = user.displayName;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('User Name'),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    // The name is stamped onto every audit entry this person writes from here
    // on, so a rename that quietly failed would leave the log naming somebody
    // who no longer goes by that.
    try {
      await userRepository.updateDisplayName(user.uid, name);
      if (context.mounted) showInfo(context, 'Name updated');
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }
}
