import 'package:flutter/material.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import 'change_password.dart';

/// The signed-in user's own profile.
///
/// This used to read the whole `users` collection and display whichever
/// document came back first, which showed a stranger's name as often as not.
class UserSettings extends StatelessWidget {
  const UserSettings(this.usermail, {super.key});

  final String usermail;

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
            MaterialPageRoute(builder: (context) => ChangePassword(usermail)),
          ),
        ),
      ],
    );
  }

  Future<void> _editDisplayName(BuildContext context, AppUser user) async {
    final controller = TextEditingController(text: user.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('User Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name != null && name.isNotEmpty) {
      await userRepository.updateDisplayName(user.uid, name);
    }
  }
}
