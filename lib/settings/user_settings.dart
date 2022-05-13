import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'change_password.dart';

class UserSettings extends StatelessWidget {
  String usermail;
  UserSettings(this.usermail, {Key? key}) : super(key: key);
  late Map<String, dynamic> users;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Settings'),
      ),
      body: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where(usermail)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                snapshot.data!.docs.forEach((DocumentSnapshot document) {
                  users = document.data() as Map<String, dynamic>;
                });

                print(users);

                return Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.title_outlined),
                      title: Text('User Name'),
                      subtitle: Text(users['name']),
                    ),
                    ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Change Password'),
                      onTap: () => changePassword(context),
                    ),
                  ],
                );
              })),
    );
  }

  changePassword(context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangePassword(usermail),
      ),
    );
  }
}
