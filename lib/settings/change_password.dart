import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChangePassword extends StatefulWidget {
  final String usermail;
  ChangePassword(this.usermail, {super.key});

  @override
  State<ChangePassword> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<ChangePassword> {
  late TextEditingController oldPasswordController,
      newPasswordController,
      reNewPasswordController;
  bool isLoading = false; // 用於顯示加載指示器
  bool showOldPassword = false;
  bool showNewPassword = false;
  bool showReNewPassword = false;

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
      body: isLoading
          ? const Center(child: CircularProgressIndicator()) // 加載狀態
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildPasswordField(
              controller: oldPasswordController,
              labelText: 'Old Password',
              obscureText: !showOldPassword,
              toggleVisibility: () {
                setState(() {
                  showOldPassword = !showOldPassword;
                });
              },
            ),
            const SizedBox(height: 16),
            _buildPasswordField(
              controller: newPasswordController,
              labelText: 'New Password',
              obscureText: !showNewPassword,
              toggleVisibility: () {
                setState(() {
                  showNewPassword = !showNewPassword;
                });
              },
            ),
            const SizedBox(height: 16),
            _buildPasswordField(
              controller: reNewPasswordController,
              labelText: 'Retype New Password',
              obscureText: !showReNewPassword,
              toggleVisibility: () {
                setState(() {
                  showReNewPassword = !showReNewPassword;
                });
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _handleChangePassword,
              icon: const Icon(Icons.check),
              label: const Text('Change Password'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String labelText,
    required bool obscureText,
    required VoidCallback toggleVisibility,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: labelText,
        suffixIcon: IconButton(
          icon: Icon(
            obscureText ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: toggleVisibility,
        ),
      ),
    );
  }

  void _handleChangePassword() {
    if (oldPasswordController.text.isEmpty ||
        newPasswordController.text.isEmpty ||
        reNewPasswordController.text.isEmpty) {
      _showSnackBar('Please fill in all fields');
      return;
    }

    if (newPasswordController.text != reNewPasswordController.text) {
      _showSnackBar('New passwords do not match');
      return;
    }

    if (newPasswordController.text.length < 6) {
      _showSnackBar('New password must be at least 6 characters');
      return;
    }

    setState(() {
      isLoading = true;
    });

    _changePassword(
      widget.usermail,
      oldPasswordController.text,
      newPasswordController.text,
    );
  }

  void _changePassword(String currentMail, String currentPassword, String newPassword) async {
    final user = FirebaseAuth.instance.currentUser;
    final credential =
    EmailAuthProvider.credential(email: currentMail, password: currentPassword);

    try {
      await user?.reauthenticateWithCredential(credential);
      await user?.updatePassword(newPassword);
      _showSnackBar('Password updated successfully', isError: false);
      oldPasswordController.clear();
      newPasswordController.clear();
      reNewPasswordController.clear();
      Navigator.pop(context); // 返回上一頁
    } on FirebaseAuthException catch (error) {
      _showSnackBar(error.message ?? 'An error occurred');
    } catch (e) {
      _showSnackBar('An unexpected error occurred');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.warning : Icons.check_circle,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: isError ? Colors.red : Colors.green,
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}
