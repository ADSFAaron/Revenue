import 'package:flutter/material.dart';

import '../database/repositories.dart';
import '../widgets/feedback.dart';
import '../widgets/page_body.dart';

/// Sets the account's password — either changing one it already has, or giving
/// it its first.
///
/// The two cases are the same screen because they end in the same place, but
/// they are not the same form. An account that signs in with Google has an
/// email and no password, so asking it for a "current password" produces a
/// field nobody can fill and a re-authentication that fails as though the
/// person mistyped. [AuthRepository.hasPasswordSignIn] is what tells the two
/// apart; nothing on the account's email can.
class ChangePassword extends StatefulWidget {
  /// Takes no email: re-authentication has to use the address the signed-in
  /// account actually has, which the auth layer already knows. Passing one down
  /// from the settings screen only created something that could go stale.
  const ChangePassword({super.key});

  @override
  State<ChangePassword> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<ChangePassword> {
  final oldPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final reNewPasswordController = TextEditingController();

  /// Read once. Linking a password is the only thing on this screen that can
  /// change the answer, and that pops the screen.
  final bool _hasPassword = authRepository.hasPasswordSignIn;

  bool _busy = false;
  bool showOldPassword = false;
  bool showNewPassword = false;
  bool showReNewPassword = false;

  @override
  void dispose() {
    oldPasswordController.dispose();
    newPasswordController.dispose();
    reNewPasswordController.dispose();
    super.dispose();
  }

  String get _title => _hasPassword ? 'Change password' : 'Set a password';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_hasPassword) ...[
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You signed in without a password, so there is no '
                          'current one to confirm. Setting one adds a second '
                          'way in — the other ways keep working.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_hasPassword) ...[
              _buildPasswordField(
                controller: oldPasswordController,
                labelText: 'Current password',
                obscureText: !showOldPassword,
                autofillHint: AutofillHints.password,
                toggleVisibility: () =>
                    setState(() => showOldPassword = !showOldPassword),
              ),
              const SizedBox(height: 16),
            ],
            _buildPasswordField(
              controller: newPasswordController,
              labelText: 'New password',
              helperText: 'At least $_minLength characters',
              obscureText: !showNewPassword,
              autofillHint: AutofillHints.newPassword,
              toggleVisibility: () =>
                  setState(() => showNewPassword = !showNewPassword),
            ),
            const SizedBox(height: 16),
            _buildPasswordField(
              controller: reNewPasswordController,
              labelText: 'Retype new password',
              obscureText: !showReNewPassword,
              autofillHint: AutofillHints.newPassword,
              toggleVisibility: () =>
                  setState(() => showReNewPassword = !showReNewPassword),
              onSubmitted: (_) => _handleSubmit(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _handleSubmit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_title),
            ),
          ],
        ),
      ),
    );
  }

  /// Firebase's own floor, the same one registration enforces.
  static const int _minLength = 6;

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String labelText,
    required bool obscureText,
    required VoidCallback toggleVisibility,
    String? helperText,
    String? autofillHint,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      enabled: !_busy,
      autofillHints: autofillHint == null ? null : [autofillHint],
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: labelText,
        helperText: helperText,
        suffixIcon: IconButton(
          tooltip: obscureText ? 'Show password' : 'Hide password',
          icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility),
          onPressed: toggleVisibility,
        ),
      ),
    );
  }

  void _handleSubmit() {
    if (_hasPassword && oldPasswordController.text.isEmpty) {
      _showSnackBar('Enter your current password');
      return;
    }

    if (newPasswordController.text.isEmpty ||
        reNewPasswordController.text.isEmpty) {
      _showSnackBar('Please fill in all fields');
      return;
    }

    if (newPasswordController.text != reNewPasswordController.text) {
      _showSnackBar('New passwords do not match');
      return;
    }

    if (newPasswordController.text.length < _minLength) {
      _showSnackBar('New password must be at least $_minLength characters');
      return;
    }

    setState(() => _busy = true);
    _submit();
  }

  Future<void> _submit() async {
    try {
      if (_hasPassword) {
        await authRepository.changePassword(
          currentPassword: oldPasswordController.text,
          newPassword: newPasswordController.text,
        );
      } else {
        await authRepository.setPassword(newPasswordController.text);
      }
      if (!mounted) return;
      _showSnackBar(
        _hasPassword ? 'Password updated' : 'Password set',
        isError: false,
      );
      Navigator.pop(context);
    } on AuthException catch (error) {
      // Re-authentication rejects the *current* password, so say so — the
      // generic wording sent people off to check the new one instead.
      if (!mounted) return;
      _showSnackBar(
        error.failure == AuthFailure.wrongPassword && _hasPassword
            ? 'That is not your current password.'
            : error.message,
      );
    } catch (_) {
      if (mounted) _showSnackBar('An unexpected error occurred');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    showSnack(context, message, isError: isError);
  }
}
