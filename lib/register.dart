import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'database/repositories.dart';
import 'login.dart';
import 'models/app_user.dart';
import 'models/invite.dart';
import 'models/store.dart';
import 'settings/store_settings_edit_menu.dart';
import 'settings/store_settings_import_menu.dart';
import 'sign_in_options.dart';
import 'widgets/page_body.dart';
import 'widgets/pre_auth_theme.dart';

/// The first thing registration asks: are you opening a store, or joining one?
///
/// It used to be inferred — six fields on one page, and whether you joined or
/// created depended on whether the store ID you pasted happened to exist
/// already. The only thing telling anyone which one they were doing was a line
/// of helper text under the last field.
class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PreAuthTheme(
      child: Scaffold(
        appBar: buildRegistrationAppBar(context),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
            child: PageBody(
              maxWidth: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Title('Get started'),
                  const SizedBox(height: 8),
                  const _Subtitle('Which of these are you doing?'),
                  const SizedBox(height: 32),
                  _PathCard(
                    icon: Icons.storefront_outlined,
                    title: 'Open a new store',
                    description:
                        'You run the place. This creates the store and makes you '
                        'its owner.',
                    onTap: () => _push(context, const OpenStoreRegistration()),
                  ),
                  const SizedBox(height: 16),
                  _PathCard(
                    icon: Icons.group_add_outlined,
                    title: 'Join an existing store',
                    description:
                        'Somebody at the store gave you a 6-character invite code.',
                    onTap: () => _push(context, const JoinStoreRegistration()),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Already have an account? '),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        ),
                        child: const Text(
                          'Login',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
}

// ---------------------------------------------------------------------------
// Path A — open a new store
// ---------------------------------------------------------------------------

/// Account → store name → menu, one question at a time.
///
/// The store id is never asked for and never shown. It is a generated
/// identifier that exists so documents have somewhere to live; the only thing
/// about the store anybody has to type is its name.
class OpenStoreRegistration extends StatefulWidget {
  const OpenStoreRegistration({super.key});

  @override
  State<OpenStoreRegistration> createState() => _OpenStoreRegistrationState();
}

class _OpenStoreRegistrationState extends State<OpenStoreRegistration> {
  final _account = _AccountFields();
  final _storeNameController = TextEditingController();

  final _pageController = PageController();
  int _step = 0;
  bool _submitting = false;
  String _storeNameError = '';

  /// Set once the store exists, which is also the point of no return: the last
  /// step is no longer part of registration, it is the first thing the owner
  /// does with a store that is already theirs.
  String? _createdStoreId;

  /// Set when the account came from Google rather than from the form.
  ///
  /// Google creates and signs in the account at the *account* step, whereas
  /// the form defers that to the store step. So this doubles as "the account
  /// already exists": [_createStore] must not try to create a second one.
  SignInResult? _google;

  @override
  void dispose() {
    // Backing out after signing in with Google, before the store exists, would
    // otherwise leave an account that can sign in and find nothing belonging to
    // it — and that then blocks the next attempt with "email already in use".
    // Best-effort and unawaited: this widget is going away either way, and the
    // alternative to a failed cleanup is no cleanup.
    _discardAbandonedGoogleAccount();

    _account.dispose();
    _storeNameController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _discardAbandonedGoogleAccount() {
    final google = _google;
    if (google == null || _createdStoreId != null) return;
    // Fire-and-forget from `dispose`, so it must not be able to throw: there
    // is no call site left to catch it and an unawaited future that fails goes
    // to the zone. `discardSignIn` swallows its own failures for exactly this.
    authRepository.discardSignIn(google);
  }

  /// Undoes the Google step so a different account can be used.
  Future<void> _useDifferentAccount() async {
    final google = _google;
    if (google == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await authRepository.discardSignIn(google);
    } finally {
      if (mounted) {
        setState(() {
          _google = null;
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PreAuthTheme(
      child: PopScope(
        canPop: _step == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_submitting) _back();
        },
        child: Scaffold(
          appBar: buildRegistrationAppBar(
            context,
            onBack: _step == 0 ? null : (_submitting ? () {} : _back),
          ),
          body: SafeArea(
            child: Column(
              children: [
                _StepDots(count: 3, current: _step),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _accountStep(),
                      _storeStep(),
                      _menuStep(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountStep() {
    final google = _google;
    if (google != null) {
      // The account already exists and is signed in. Showing the form again
      // would invite somebody to fill in an email that is no longer used for
      // anything.
      return _StepBody(
        title: 'Your account',
        subtitle: 'Signed in with Google.',
        children: [
          _SignedInBanner(result: google),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _submitting ? null : _useDifferentAccount,
              child: const Text('Not you? Use a different account'),
            ),
          ),
          const SizedBox(height: 16),
          _PrimaryButton(
            label: 'Continue',
            onPressed: _submitting ? null : _next,
          ),
        ],
      );
    }

    return _StepBody(
      title: 'Your account',
      subtitle: 'This is how you sign in.',
      children: [
        _account.build(onSubmit: _next),
        const SizedBox(height: 8),
        _PrimaryButton(
          label: 'Continue',
          onPressed: _submitting ? null : _next,
        ),
        const SizedBox(height: 24),
        SignInOptions(busy: _submitting, onGoogle: _continueWithGoogle),
      ],
    );
  }

  Widget _storeStep() => _StepBody(
        title: 'Your store',
        subtitle: 'You can change this later in Store Settings.',
        children: [
          _LabelledField(
            label: 'Store name',
            controller: _storeNameController,
            errorText: _storeNameError,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _next(),
          ),
          const SizedBox(height: 8),
          _PrimaryButton(
            label: 'Create store',
            busy: _submitting,
            onPressed: _submitting ? null : _next,
          ),
          const SizedBox(height: 16),
          const _Note(
            'Tax, trading-day cutoff, daily targets and delivery platforms all '
            'start at sensible defaults and are editable in Store Settings. '
            'Registration does not ask about any of them.',
          ),
        ],
      );

  /// The menu is deliberately left empty rather than seeded with a starter one.
  /// A fake menu that looks real invites somebody to ring up a sale against a
  /// dish this kitchen has never sold.
  ///
  /// Which is exactly why the photo goes first. Typing forty dishes into a
  /// phone is the moment a new store gives up on the app, and it is the moment
  /// it is least invested in seeing it through. Nothing is written without
  /// being checked on screen either way.
  Widget _menuStep() => _StepBody(
        title: 'Your store is ready',
        subtitle: 'The menu is empty. Nothing can be rung up until it is not.',
        children: [
          _PrimaryButton(
            label: 'Import menu from a photo',
            onPressed: () => _finish(next: _MenuStart.importFromPhoto),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => _finish(next: _MenuStart.addByHand),
              child: const Text('Add dishes manually'),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => _finish(next: _MenuStart.later),
              child: const Text('Skip for now'),
            ),
          ),
          const SizedBox(height: 16),
          const _Note(
            'Dishes can be added at any time from Store Settings → Edit Menu, '
            'by photo or by hand.',
          ),
        ],
      );

  void _back() {
    if (_step == 0) return;
    // Step 2 is past the point of no return — the store exists and the account
    // is signed in, so there is nothing to go back to and change. Backing out
    // of it is just declining to add dishes right now.
    if (_step == 2) {
      _finish(next: _MenuStart.later);
      return;
    }
    setState(() => _step -= 1);
    _pageController.animateToPage(
      _step,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _next() async {
    if (_submitting) return;

    if (_step == 0) {
      if (_google == null && !_account.validate()) return;
      setState(() => _step = 1);
      await _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    if (_step == 1) await _createStore();
  }

  /// Signs in with Google, which creates the account here rather than at the
  /// store step.
  ///
  /// A Google account that already has a profile belongs to a store already —
  /// that person is not registering, they are signing in, so send them
  /// straight into the app instead of asking them to name a second store.
  Future<void> _continueWithGoogle() async {
    if (_submitting) return;
    try {
      final result = await authRepository.signInWithGoogle();

      if (await userRepository.fetch(result.uid) != null) {
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

      if (!mounted) return;
      setState(() {
        _google = result;
        _step = 1;
      });
      await _pageController.animateToPage(1,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } on AuthException catch (e) {
      if (e.failure == AuthFailure.cancelled) return;
      if (mounted && !_account.showAuthError(e)) {
        showRegistrationError(context, e.message);
      }
    }
  }

  Future<void> _createStore() async {
    final storeName = _storeNameController.text.trim();
    setState(() =>
        _storeNameError = storeName.isEmpty ? 'Enter the store name' : '');
    if (storeName.isNotEmpty && _google == null && !_account.validate()) {
      // Something on the first step no longer passes — send them back to it
      // rather than failing against Firebase with a message they cannot act on.
      setState(() => _step = 0);
      await _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }
    if (storeName.isEmpty) return;

    setState(() => _submitting = true);
    final google = _google;
    final email = google?.email ?? _account.email;

    String? uid;
    var accountIsNew = true;
    try {
      if (google != null) {
        uid = google.uid;
        // Only undo an account this flow brought into existence. Somebody who
        // signed in with a Google account they already had should keep it.
        accountIsNew = google.isNewAccount;
      } else {
        uid = await authRepository.register(
          email: email,
          password: _account.password,
        );
      }

      // Internal from here on: generated, never displayed, never typed.
      final storeId = const Uuid().v4();

      // The user document goes first and claims the store id while no store
      // holds it — that is exactly the shape the rules allow somebody to
      // create themselves as an `owner` in.
      await userRepository.create(AppUser(
        uid: uid,
        email: email,
        displayName: google?.displayName.isNotEmpty == true
            ? google!.displayName
            : _account.displayName,
        storeId: storeId,
        role: UserRole.owner,
      ));

      // No categories and no seeded dishes. An empty menu is honest.
      await storeRepository.create(Store(id: storeId, name: storeName));

      if (!mounted) return;
      setState(() {
        _createdStoreId = storeId;
        _step = 2;
      });
      await _pageController.animateToPage(2,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } on AuthException catch (e) {
      if (!mounted) return;
      // Every auth failure here is about a field on the first step.
      setState(() => _step = 0);
      await _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      if (mounted && !_account.showAuthError(e)) {
        showRegistrationError(context, e.message);
      }
    } catch (e) {
      // The sign-in account exists but its store does not, which would leave an
      // account that can sign in and then find nothing belonging to it.
      if (uid != null && accountIsNew) {
        await authRepository.deleteCurrentAccount();
        if (mounted) setState(() => _google = null);
      }
      if (mounted)
        showRegistrationError(context, 'Could not create the store: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _finish({required _MenuStart next}) {
    final storeId = _createdStoreId;
    // Resolved before the pop: popUntil takes this route off the tree, and
    // `context` is defunct from that moment on — looking the navigator up
    // again afterwards would throw.
    final navigator = Navigator.of(context);

    // Back to the root, which is watching auth state and will show the shell
    // through the session gate.
    navigator.popUntil((route) => route.isFirst);
    if (storeId == null || next == _MenuStart.later) return;

    navigator.push(MaterialPageRoute(builder: (_) => StoreEditMenu(storeId)));
    if (next == _MenuStart.importFromPhoto) {
      // Pushed on top of Edit Menu rather than instead of it, so closing the
      // importer lands on the menu it just filled. An import is where setting
      // a menu up starts, not where it finishes — icons still need picking and
      // costs still need filling in.
      navigator
          .push(MaterialPageRoute(builder: (_) => StoreImportMenu(storeId)));
    }
  }
}

/// Where somebody is sent once their store exists.
enum _MenuStart { importFromPhoto, addByHand, later }

// ---------------------------------------------------------------------------
// Path B — join an existing store
// ---------------------------------------------------------------------------

/// Invite code first, account second.
///
/// The order is the whole point: nobody should fill in a page and only then
/// discover they typed the code wrong. On a good code the next screen names
/// the store, so joining the wrong one is caught before an account exists.
class JoinStoreRegistration extends StatefulWidget {
  const JoinStoreRegistration({super.key});

  @override
  State<JoinStoreRegistration> createState() => _JoinStoreRegistrationState();
}

class _JoinStoreRegistrationState extends State<JoinStoreRegistration> {
  final _account = _AccountFields();
  final _codeController = TextEditingController();

  final _pageController = PageController();
  int _step = 0;
  bool _submitting = false;
  String _codeError = '';

  /// The validated invite. Holding it is what lets the account step name the
  /// store — the person does not belong to it yet and so cannot read it.
  Invite? _invite;

  @override
  void dispose() {
    _account.dispose();
    _codeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PreAuthTheme(
      child: PopScope(
        canPop: _step == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_submitting) _back();
        },
        child: Scaffold(
          appBar: buildRegistrationAppBar(
            context,
            onBack: _step == 0 ? null : (_submitting ? () {} : _back),
          ),
          body: SafeArea(
            child: Column(
              children: [
                _StepDots(count: 2, current: _step),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [_codeStep(), _accountStep()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _codeStep() => _StepBody(
        title: 'Your invite code',
        subtitle:
            'Six characters, from whoever manages the store. Codes work once '
            'and expire after 30 minutes.',
        children: [
          _LabelledField(
            label: 'Invite code',
            controller: _codeController,
            errorText: _codeError,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            style: const TextStyle(
              fontSize: 26,
              letterSpacing: 8,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            inputFormatters: [
              // Order matters: strip the separators first, then cap. A limiter
              // running first would count the spaces in a pasted "abc - 234"
              // and truncate real characters off the end.
              _InviteCodeFormatter(),
              LengthLimitingTextInputFormatter(Invite.codeLength),
            ],
            onSubmitted: (_) => _checkCode(),
          ),
          const SizedBox(height: 8),
          _PrimaryButton(
            label: 'Check code',
            busy: _submitting,
            onPressed: _submitting ? null : _checkCode,
          ),
        ],
      );

  Widget _accountStep() {
    final invite = _invite;
    return _StepBody(
      title: 'Your account',
      subtitle: 'This is how you sign in.',
      children: [
        if (invite != null) ...[
          _JoiningBanner(invite: invite),
          const SizedBox(height: 24),
        ],
        _account.build(onSubmit: _join),
        const SizedBox(height: 8),
        _PrimaryButton(
          label: 'Join store',
          busy: _submitting,
          onPressed: _submitting ? null : _join,
        ),
        const SizedBox(height: 24),
        SignInOptions(busy: _submitting, onGoogle: _joinWithGoogle),
      ],
    );
  }

  /// Joins with a Google account instead of a new email and password.
  ///
  /// Same two writes as [_join] — the account, then the redemption — but the
  /// account comes from Google. A Google account that already has a profile is
  /// already in a store, and a person belongs to exactly one, so that is a
  /// refusal rather than a second membership.
  Future<void> _joinWithGoogle() async {
    if (_submitting) return;
    final invite = _invite;
    if (invite == null) return _back();

    setState(() => _submitting = true);
    SignInResult? account;
    try {
      account = await authRepository.signInWithGoogle();

      if (await userRepository.fetch(account.uid) != null) {
        await authRepository.discardSignIn(account);
        if (mounted) {
          showRegistrationError(
            context,
            'That Google account already belongs to a store. Sign in with it '
            'instead, or use a different account to join this one.',
          );
        }
        return;
      }

      await inviteRepository.redeem(
        code: invite.code,
        uid: account.uid,
        email: account.email,
        displayName: account.displayName.isNotEmpty
            ? account.displayName
            : account.email,
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (e.failure == AuthFailure.cancelled) return;
      if (mounted && !_account.showAuthError(e)) {
        showRegistrationError(context, e.message);
      }
    } on InviteException catch (e) {
      await _undo(account);
      if (!mounted) return;
      setState(() {
        _codeError = e.message;
        _step = 0;
        _invite = null;
      });
      await _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } catch (e) {
      await _undo(account);
      if (mounted) {
        // Translated rather than interpolated: `$e` on a Firestore failure
        // opens with `[cloud_firestore/permission-denied]`, which is an error
        // code shown to somebody halfway through joining a shop.
        showRegistrationError(
            context, 'Could not join the store. ${describeFailure(e).message}');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Puts a half-finished Google registration back.
  ///
  /// An account created by this flow and left with no store is worse than no
  /// account: it can sign in and find nothing, and it blocks the person's next
  /// attempt with "email already in use". One they already had is theirs, so
  /// it is only signed out.
  Future<void> _undo(SignInResult? account) async {
    if (account == null) return;
    await authRepository.discardSignIn(account);
  }

  void _back() {
    if (_step == 0) return;
    setState(() {
      _step = 0;
      _invite = null;
    });
    _pageController.animateToPage(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _checkCode() async {
    if (_submitting) return;
    final typed = Invite.normalise(_codeController.text);
    setState(() => _codeError = Invite.isWellFormed(typed)
        ? ''
        : 'An invite code is ${Invite.codeLength} characters');
    if (_codeError.isNotEmpty) return;

    setState(() => _submitting = true);
    try {
      final invite = await inviteRepository.validate(typed);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _step = 1;
      });
      await _pageController.animateToPage(1,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } on InviteException catch (e) {
      if (mounted) setState(() => _codeError = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _join() async {
    if (_submitting) return;
    final invite = _invite;
    if (invite == null) return _back();
    if (!_account.validate()) return;

    setState(() => _submitting = true);
    final email = _account.email;

    String? uid;
    try {
      uid = await authRepository.register(
        email: email,
        password: _account.password,
      );

      // Marks the code used and writes `users/{uid}` in one commit, so two
      // people racing on the same code produce exactly one member.
      await inviteRepository.redeem(
        code: invite.code,
        uid: uid,
        email: email,
        displayName: _account.displayName,
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (mounted && !_account.showAuthError(e)) {
        showRegistrationError(context, e.message);
      }
    } on InviteException catch (e) {
      // Somebody spent the code between validating it and finishing the form.
      // The account cannot stay: it belongs to no store.
      if (uid != null) await authRepository.deleteCurrentAccount();
      if (!mounted) return;
      setState(() {
        _codeError = e.message;
        _step = 0;
        _invite = null;
      });
      await _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } catch (e) {
      if (uid != null) await authRepository.deleteCurrentAccount();
      if (mounted)
        showRegistrationError(context, 'Could not join the store: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

/// Email, password and display name — identical on both paths, so they are
/// written once.
///
/// There is no "confirm password" field. The show/hide toggle does the same
/// job, and a password that gets forgotten anyway has Firebase's reset flow.
class _AccountFields extends ChangeNotifier {
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
            _LabelledField(
              label: 'Email',
              controller: emailController,
              errorText: _emailError,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            _LabelledField(
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
                icon: Icon(
                    _showPassword ? Icons.visibility : Icons.visibility_off),
              ),
            ),
            _LabelledField(
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

/// The app bar every registration screen shares: transparent, so it always
/// matches the scaffold background instead of drifting from it.
PreferredSizeWidget buildRegistrationAppBar(
  BuildContext context, {
  VoidCallback? onBack,
}) {
  return AppBar(
    systemOverlayStyle: SystemUiOverlayStyle.dark,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
    leading: IconButton(
      tooltip: 'Back',
      icon: Icon(Icons.arrow_back, color: Colors.grey[700], size: 20),
      onPressed: onBack ?? () => Navigator.pop(context),
    ),
  );
}

void showRegistrationError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    backgroundColor: Colors.red,
    duration: const Duration(seconds: 6),
    content: Text(message),
  ));
}

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Every step of both wizards renders through here, so one cap covers all
    // of them.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
      child: PageBody(
        maxWidth: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Title(title),
            const SizedBox(height: 8),
            _Subtitle(subtitle),
            const SizedBox(height: 28),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      );
}

class _Subtitle extends StatelessWidget {
  const _Subtitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, color: Colors.grey[700], height: 1.4),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4),
      );
}

/// Which step of how many, without pretending to be a Material Stepper.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final done = i <= current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 6,
            width: i == current ? 28 : 12,
            decoration: BoxDecoration(
              color: done ? Colors.black87 : Colors.grey[300],
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[700], height: 1.4),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// "You are joining: `<store name>`" — shown before an account exists, which is
/// the only moment a mistyped code is still cheap to fix.
class _JoiningBanner extends StatelessWidget {
  const _JoiningBanner({required this.invite});

  final Invite invite;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black26),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are joining',
                  style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                ),
                Text(
                  invite.storeName.isEmpty ? 'this store' : invite.storeName,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  'as ${invite.role.label.toLowerCase()}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Signed in as …", once Google has answered and there is nothing left to
/// type on this step.
class _SignedInBanner extends StatelessWidget {
  const _SignedInBanner({required this.result});

  final SignInResult result;

  @override
  Widget build(BuildContext context) {
    final name =
        result.displayName.isNotEmpty ? result.displayName : result.email;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black26),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                if (result.email.isNotEmpty && result.email != name)
                  Text(
                    result.email,
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelledField extends StatelessWidget {
  const _LabelledField({
    required this.label,
    required this.controller,
    required this.errorText,
    this.obscureText = false,
    this.helperText,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.autofillHints,
    this.onSubmitted,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final String label;
  final TextEditingController controller;
  final String errorText;
  final bool obscureText;
  final String? helperText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final List<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          autofillHints: autofillHints,
          onSubmitted: onSubmitted,
          style: style,
          textAlign: textAlign,
          decoration: InputDecoration(
            errorText: errorText.isEmpty ? null : errorText,
            errorMaxLines: 3,
            helperText: helperText,
            helperMaxLines: 2,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            border: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey)),
            enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey)),
            suffixIcon: suffixIcon,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 3, left: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: Colors.black),
      ),
      child: MaterialButton(
        height: 60,
        minWidth: double.infinity,
        onPressed: busy ? null : onPressed,
        color: Colors.greenAccent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        child: busy
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                label,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}

/// Upper-cases as you type and silently drops anything outside the code
/// alphabet, so a code copied off a scrap of paper with a hyphen in it still
/// works.
class _InviteCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = Invite.normalise(newValue.text);
    if (cleaned == newValue.text) return newValue;
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}
