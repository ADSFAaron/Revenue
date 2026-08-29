import 'package:flutter/material.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import '../widgets/feedback.dart';
import 'change_password.dart';
import 'user_passkeys.dart';

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
              return const Center(child: Text('Failed to load user data.'));
            }
            if (!snapshot.hasData && snapshot.connectionState != ConnectionState.active) {
              return const Center(child: CircularProgressIndicator());
            }

            final user = snapshot.data;
            if (user == null) {
              return const Center(child: Text('No user found.'));
            }
            return _buildUserSettings(context, user);
          },
        ),
      ),
    );
  }

  Widget _buildUserSettings(BuildContext context, AppUser user) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('User Name'),
          subtitle:
              Text(user.displayName.isEmpty ? 'No Name' : user.displayName),
          trailing: const Icon(Icons.edit_outlined),
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
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Change Password'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ChangePassword()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.fingerprint),
          title: const Text('Passkeys'),
          subtitle: const Text(
              'Sign in with a fingerprint, face or screen lock'),
          trailing: const Icon(Icons.keyboard_arrow_right_outlined),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const UserPasskeys()),
          ),
        ),
      ],
    );
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
