import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'change_password.dart';

class UserSettings extends StatelessWidget {
  final String usermail;
  final User currentUser = FirebaseAuth.instance.currentUser!;

  UserSettings(this.usermail, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {

    print("Current User: ${currentUser.email}");

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Settings'),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .snapshots(),
          builder: (context, snapshot) {

            print(snapshot.data);

            if (snapshot.hasError) {
              return const Center(child: Text('Failed to load user data.'));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.data == null || snapshot.data!.docs.isEmpty) {
              print("Final User Data: ${snapshot.data}");

              return const Center(child: Text('No user found.'));
            }

            // Assuming a single user document matches the query
            final userData =
            snapshot.data!.docs.first.data() as Map<String, dynamic>;

            print("Final User Data: $userData");

            return _buildUserSettings(context, userData);
          },
        ),
      ),
    );
  }

  Widget _buildUserSettings(BuildContext context, Map<String, dynamic> userData) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('User Name'),
          subtitle: Text(userData['name'] ?? 'No Name'),
        ),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: const Text('Email'),
          subtitle: Text(currentUser.email ?? 'No Email'),
        ),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Change Password'),
          onTap: () => _navigateToChangePassword(context),
        ),
      ],
    );
  }

  void _navigateToChangePassword(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangePassword(usermail),
      ),
    );
  }
}
