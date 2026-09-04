// Split out of lib/register.dart, which had grown to 1326 lines — the largest
// UI file in the project — by carrying the chooser, both registration flows and
// every piece of furniture they share in one place.

import 'package:flutter/material.dart';

import '../database/repositories.dart';
import 'registration_ui.dart';

/// Email, password and display name — identical on both paths, so they are
/// written once.
///
/// There is no "confirm password" field. The show/hide toggle does the same
/// job, and a password that gets forgotten anyway has Firebase's reset flow.
class AccountFields extends ChangeNotifier {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();

  bool _showPassword = false;
  String _emailError = '';
  String _passwordError = '';
  String _nameError = '';

  String get email => emailController.text.trim();
  String get password => passwordController.text;
  String get displayName => nameController.text.trim();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    super.dispose();
  }

  /// Firebase's own floor. Enforcing it here means a whole round trip is not
  /// spent discovering it.
  static const int minPasswordLength = 6;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool validate() {
    _emailError = email.isEmpty
        ? 'Enter your email'
        : (_emailPattern.hasMatch(email)
              ? ''
              : 'That is not a valid email address');
    _passwordError = password.length < minPasswordLength
        ? 'At least $minPasswordLength characters'
        : '';
    _nameError = displayName.isEmpty ? 'Enter your name' : '';
    notifyListeners();
    return _emailError.isEmpty && _passwordError.isEmpty && _nameError.isEmpty;
  }

  /// Puts the failure where the person can act on it: under the field that
  /// caused it when there is one, in a snackbar when there is not.
  ///
  /// Returns false when it had nowhere to put the message, so the caller can
  /// show it some other way.
  bool showAuthError(AuthException e) {
    switch (e.failure) {
      case AuthFailure.weakPassword:
        _passwordError = e.message;
      case AuthFailure.emailInUse:
      case AuthFailure.invalidEmail:
        _emailError = e.message;
      default:
        return false;
    }
    notifyListeners();
    return true;
  }

  Widget build({required VoidCallback onSubmit}) => ListenableBuilder(
    listenable: this,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabelledField(
          label: 'Email',
          controller: emailController,
          errorText: _emailError,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
        ),
        LabelledField(
          label: 'Password',
          controller: passwordController,
          errorText: _passwordError,
          obscureText: !_showPassword,
          helperText: 'At least $minPasswordLength characters',
          autofillHints: const [AutofillHints.newPassword],
          suffixIcon: IconButton(
            tooltip: _showPassword ? 'Hide password' : 'Show password',
            onPressed: () {
              _showPassword = !_showPassword;
              notifyListeners();
            },
            icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
          ),
        ),
        LabelledField(
          label: 'Your name',
          controller: nameController,
          errorText: _nameError,
          helperText: 'Shown on the staff list and against orders you take',
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.name],
          onSubmitted: (_) => onSubmit(),
        ),
      ],
    ),
  );
}
