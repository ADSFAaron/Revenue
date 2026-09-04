import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/repositories.dart';
import '../widgets/feedback.dart';
import 'choose_path.dart';
import 'entry_button.dart';
import 'entry_ui.dart';
import 'sign_in_options.dart';

/// Signing in to an account this device does not already know.
///
/// Reached from the operator picker's "Other account", or shown in its place
/// on a device nobody has signed in on yet. It is deliberately no longer the
/// front door: on a counter tablet the front door is a list of names, and
/// typing an address is what you do the first time and then rarely again.
class SignInScreen extends StatefulWidget {
  const SignInScreen({this.email, super.key});

  /// Filled in when the picker knows who is trying to get in — somebody whose
  /// passkey failed, or who has none on this device. Nobody should have to
  /// type an address the device just showed them.
  final String? email;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late final emailController = TextEditingController(text: widget.email ?? '');
  final passwordController = TextEditingController();

  String _emailError = '';
  String _passwordError = '';

  /// Latches the button while a request is in flight. This replaced a
  /// full-screen modal spinner that was only dismissed on two of its paths,
  /// so anything unexpected left an untappable circle with no way out.
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String get _email => emailController.text.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildEntryAppBar(context),
      body: SafeArea(
        child: AutofillGroup(
          child: EntryBody(
            children: [
              const EntryHeader(),
              const SizedBox(height: 32),
              const StepTitle('Sign in'),
              const SizedBox(height: 8),
              const StepSubtitle('With the account you use for this shop.'),
              const SizedBox(height: 28),
              LabelledField(
                label: 'Email',
                controller: emailController,
                errorText: _emailError,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 16),
              LabelledField(
                label: 'Password',
                controller: passwordController,
                errorText: _passwordError,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _signIn(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _resetPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 8),
              EntryButton(
                label: 'Sign in',
                busy: _busy,
                onPressed: _signIn,
              ),
              const SizedBox(height: 8),
              SignInOptions(
                busy: _busy,
                onGoogle: _signInWithGoogle,
                onPasskey: _signInWithPasskey,
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('New to Revenue? '),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ChoosePathScreen(),
                              ),
                            ),
                    child: const Text('Get started'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() {
      _emailError = _email.isEmpty ? 'Enter your email' : '';
      _passwordError =
          passwordController.text.isEmpty ? 'Enter your password' : '';
    });
    if (_emailError.isNotEmpty || _passwordError.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      await authRepository.signIn(
        email: _email,
        password: passwordController.text,
      );
      // Tells the password manager the form succeeded, which is what makes it
      // offer to save. Without it a manager that filled the form has no idea
      // whether what it filled was right.
      TextInput.finishAutofillContext();
      _leave();
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _passwordError = e.message);
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      await authRepository.signInWithGoogle();
      _leave();
    } on AuthException catch (e) {
      // Backing out of the sheet is a decision, not a failure.
      if (e.failure != AuthFailure.cancelled && mounted) {
        showEntryError(context, e.message);
      }
    }
  }

  Future<void> _signInWithPasskey() async {
    try {
      final session = await passkeyRepository.signIn();
      // The roster learns which credential belongs to whom here, from the
      // person who has just used it — the only place that can be known without
      // asking a server "whose passkeys are these", which from a signed-out
      // screen would be an enumeration oracle.
      await deviceAccounts.rememberPasskey(
        session.user.uid,
        session.credentialId,
      );
      _leave();
    } on PasskeyException catch (e) {
      if (e.failure != PasskeyFailure.cancelled && mounted) {
        showEntryError(context, e.message);
      }
    }
  }

  /// Takes this screen off the stack once somebody is in.
  ///
  /// The root swaps the *home route's* content when the auth state changes —
  /// it cannot remove routes pushed on top of it, and this is one of those. So
  /// signing in successfully used to leave the person looking at the form they
  /// had just filled in, with the app behind it, and pressing Back was what
  /// appeared to complete the sign-in.
  ///
  /// The registration flows deliberately do the opposite and stay: an account
  /// exists halfway through them and the flow has work left to do. Popping is
  /// this screen's business because this screen's whole job is finished the
  /// moment it succeeds.
  void _leave() {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  Future<void> _resetPassword() async {
    if (_email.isEmpty) {
      setState(() => _emailError = 'Enter your email first');
      return;
    }
    setState(() => _busy = true);
    try {
      await authRepository.sendPasswordReset(_email);
      if (mounted) {
        showInfo(context, 'If that address has an account, a reset link is on '
            'its way.');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _emailError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
