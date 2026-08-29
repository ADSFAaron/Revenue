import 'package:flutter/material.dart';

import '../database/repositories.dart';
import '../widgets/feedback.dart';

class ChangePassword extends StatefulWidget {
  /// Takes no email: re-authentication has to use the address the signed-in
  /// account actually has, which the auth layer already knows. Passing one down
  /// from the settings screen only created something that could go stale.
  const ChangePassword({super.key});

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
          tooltip: obscureText ? 'Show password' : 'Hide password',
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
      oldPasswordController.text,
      newPasswordController.text,
    );
  }

  void _changePassword(String currentPassword, String newPassword) async {
    try {
      await authRepository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (!mounted) return;
      _showSnackBar('Password updated successfully', isError: false);
      oldPasswordController.clear();
      newPasswordController.clear();
      reNewPasswordController.clear();
      Navigator.pop(context);
    } on AuthException catch (error) {
      // Re-authentication rejects the *current* password, so say so — the
      // generic wording sent people off to check the new one instead.
      if (!mounted) return;
      _showSnackBar(error.failure == AuthFailure.wrongPassword
          ? 'That is not your current password.'
          : error.message);
    } catch (e) {
      if (mounted) _showSnackBar('An unexpected error occurred');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    showSnack(context, message, isError: isError);
  }
}
