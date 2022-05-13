import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChangePassword extends StatefulWidget {
  String usermail;
  ChangePassword(this.usermail, {Key? key}) : super(key: key);

  @override
  State<ChangePassword> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<ChangePassword> {
  late TextEditingController oldPasswordController,
      newPasswordController,
      reNewPasswordController;

  @override
  void initState() {
    super.initState();
    oldPasswordController = TextEditingController();
    newPasswordController = TextEditingController();
    reNewPasswordController = TextEditingController();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Password'),
      ),
      body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where(widget.usermail)
              .snapshots(),
          builder: (context, snapshot) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: oldPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Old Password',
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'New Password',
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: reNewPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Retype New Password',
                    ),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                      onPressed: () {
                        if (oldPasswordController.text.isNotEmpty &&
                            newPasswordController.text.isNotEmpty &&
                            reNewPasswordController.text.isNotEmpty) {
                          if (newPasswordController.text ==
                              reNewPasswordController.text) {
                            _changePassword(
                                widget.usermail,
                                oldPasswordController.text,
                                newPasswordController.text,
                                context);
                          }
                        }
                      },
                      icon: Icon(Icons.check),
                      label: Text('Change Password')),
                ],
              ),
            );
          }),
    );
  }

  void _changePassword(String currentMail, String currentPassword,
      String newPassword, BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    final cred = EmailAuthProvider.credential(
        email: currentMail, password: currentPassword);

    user?.reauthenticateWithCredential(cred).then((value) {
      user.updatePassword(newPassword).then((_) {
        //Success, do something
        Navigator.pop(context);
      }).catchError((error) {
        //Error, do something
        final snackBar = SnackBar(
          backgroundColor: Colors.red,
          duration: Duration(milliseconds: 2000),
          content: Row(
            children: [
              const Icon(
                Icons.warning_outlined,
                color: Colors.white,
              ),
              Text('Error: ${error.toString()}'),
            ],
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      });
    }).catchError((err) {});
  }
}
