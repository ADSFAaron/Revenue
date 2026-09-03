import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'animation/fade_animation.dart';
import 'database/repositories.dart';
import 'widgets/feedback.dart';
import 'register.dart';
import 'sign_in_options.dart';
import 'widgets/page_body.dart';
import 'widgets/pre_auth_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String errorString = "";
  bool errorVisible = false;

  /// Latches the sign-in button while a request is in flight.
  ///
  /// Replaces a `showDialog(barrierDismissible: false)` spinner that was only
  /// dismissed on the success path and on `AuthException`. Anything else — a
  /// plugin failure, a `TypeError` from a malformed response — left a
  /// full-screen, untappable spinner with no way out but killing the app.
  bool _signingIn = false;

  bool _obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PreAuthTheme(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          // Dark status-bar icons, because the bar behind them is light.
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          // Transparent rather than a fixed colour, so the bar always picks up
          // the scaffold background instead of drifting from it when the theme
          // changes. surfaceTint and scrolledUnderElevation are what would
          // otherwise tint it the moment content scrolls underneath.
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Back',
            icon: Icon(
              Icons.arrow_back,
              color: Colors.grey[700],
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          // A sign-in form has no reason to be 1400pt wide in a browser.
          child: PageBody(
            maxWidth: 480,
            child: ConstrainedBox(
              // minHeight rather than a fixed height: with the Google and passkey
              // buttons added, a short screen has to be allowed to scroll rather
              // than overflow.
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 100,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      FadeAnimation(
                        0,
                        Text(
                          "Login",
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black),
                        ),
                      ),
                      SizedBox(height: 10),
                      FadeAnimation(
                          100,
                          Text(
                            "Login to your account",
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: Colors.grey[700]),
                          )),
                      SizedBox(height: 10),
                      // Was a bare red DecoratedBox with no padding or radius that
                      // shoved the fields down as it appeared.
                      Visibility(
                        visible: errorVisible,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(40, 0, 40, 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFE57373)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Color(0xFFB71C1C), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    errorString,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                            color: const Color(0xFFB71C1C)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding:
                            EdgeInsets.symmetric(vertical: 20, horizontal: 40),
                        // Without this the hints on the fields are advisory only —
                        // the platform needs a group to know the two belong to one
                        // credential and to offer to save it.
                        child: AutofillGroup(
                          child: Column(
                            children: <Widget>[
                              FadeAnimation(
                                  250,
                                  makeInput(
                                      label: "Email",
                                      controller: emailController)),
                              FadeAnimation(
                                  500,
                                  makeInput(
                                      label: "Password",
                                      isPassword: true,
                                      controller: passwordController)),
                              FadeAnimation(
                                600,
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed:
                                        _signingIn ? null : _resetPassword,
                                    child: const Text('Forgot password?'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      FadeAnimation(
                          750,
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 40,
                            ),
                            child: Container(
                              padding: EdgeInsets.only(top: 3, left: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(color: Colors.black),
                              ),
                              child: MaterialButton(
                                height: 60,
                                minWidth: double.infinity,
                                onPressed: _signingIn
                                    ? null
                                    : () {
                                        signIn(emailController.text.trim(),
                                            passwordController.text.trim());
                                      },
                                color: Colors.greenAccent,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(50)),
                                child: _signingIn
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black54),
                                      )
                                    : Text(
                                        'Login',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600),
                                      ),
                              ),
                            ),
                          )),
                      FadeAnimation(
                        900,
                        Padding(
                          padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
                          child: SignInOptions(
                            onGoogle: signInWithGoogle,
                            onPasskey: signInWithPasskey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  FadeAnimation(
                      1000,
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Don't have an account? "),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const RegisterPage()),
                            ),
                            child: Text(
                              "Sign UP",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      )),
                  FadeAnimation(
                    1250,
                    SizedBox(
                      height: MediaQuery.of(context).size.height / 4,
                      child: SvgPicture.asset(
                        'assets/login_bg.svg',
                        fit: BoxFit.fitHeight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> signIn(String email, String password) async {
    if (_signingIn) return;
    if (email.isEmpty || password.isEmpty) {
      _showError('Please fill all fields');
      return;
    }

    setState(() => _signingIn = true);
    try {
      await authRepository.signIn(email: email, password: password);
      // Prompts the platform's "save this password?" sheet.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      // Back to the root, which is watching auth state and shows the shell
      // through the session gate.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      // The catch-all the modal spinner never had.
      if (mounted) _showError(describeFailure(e).message);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  /// Emails a reset link. There was no way back into an account from this
  /// screen at all — the only password screen in the app assumed you were
  /// already signed in.
  Future<void> _resetPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email address first, then tap this again.');
      return;
    }
    try {
      await authRepository.sendPasswordReset(email);
      if (!mounted) return;
      showInfo(
        context,
        'If $email has an account, a reset link is on its way.',
      );
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      final result = await authRepository.signInWithGoogle();
      await _land(result);
    } on AuthException catch (e) {
      // Dismissing the Google sheet is a decision, not a failure.
      if (e.failure != AuthFailure.cancelled) _showError(e.message);
    }
  }

  Future<void> signInWithPasskey() async {
    try {
      await _land(await passkeyRepository.signIn());
    } on PasskeyException catch (e) {
      if (e.failure != PasskeyFailure.cancelled) _showError(e.message);
    }
  }

  /// Sends a successful sign-in on to the app, or undoes it.
  ///
  /// Google will happily create an account for anybody who taps the button,
  /// including somebody who has never registered. That account has no
  /// `users/{uid}` document and belongs to no store, so letting it through
  /// would drop them on the session gate's "no profile" screen with no idea
  /// what to do. Better to put it back the way it was and say which button
  /// they wanted.
  Future<void> _land(SignInResult result) async {
    if (await userRepository.fetch(result.uid) != null) {
      if (!mounted) return;
      // Back to the root, which is watching auth state and shows the shell
      // through the session gate.
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    // Best-effort, and it has to be: this runs after a *successful* sign-in
    // that turned out to lead nowhere, and the callers above catch
    // `AuthException` and `PasskeyException` only. A bare `signOut()` throwing
    // a raw `FirebaseAuthException` here escaped all of them, so the person
    // saw a framework error instead of the sentence below telling them which
    // button they actually wanted.
    await authRepository.discardSignIn(result);

    _showError(
      'There is no Revenue account for that sign-in yet. Tap Sign UP to open '
      'a store, or to join one with an invite code.',
    );
  }

  void _showError(String message) {
    if (mounted) showError(context, message);
  }

  /// One labelled field.
  ///
  /// The register screen has had `autofillHints` and a typed keyboard since it
  /// was rewritten; this one had neither, so a password manager could fill the
  /// form you use once and not the one you use every day, and the email field
  /// opened a keyboard with no `@` on it.
  Widget makeInput({
    required String label,
    bool isPassword = false,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
        ),
        SizedBox(height: 5),
        TextField(
          controller: controller,
          obscureText: isPassword && _obscurePassword,
          enabled: !_signingIn,
          keyboardType:
              isPassword ? TextInputType.text : TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: !isPassword,
          autofillHints: [
            isPassword ? AutofillHints.password : AutofillHints.email,
          ],
          textInputAction:
              isPassword ? TextInputAction.done : TextInputAction.next,
          onSubmitted: (value) {
            if (isPassword) {
              signIn(
                  emailController.text.trim(), passwordController.text.trim());
            }
          },
          decoration: InputDecoration(
            contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            border:
                OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            enabledBorder:
                OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            suffixIcon: isPassword
                ? IconButton(
                    tooltip:
                        _obscurePassword ? 'Show password' : 'Hide password',
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  )
                : null,
          ),
        ),
        SizedBox(height: 20),
      ],
    );
  }
}
