// Split out of lib/register.dart, which had grown to 1326 lines — the largest
// UI file in the project — by carrying the chooser, both registration flows and
// every piece of furniture they share in one place.

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import '../models/store.dart';
import '../settings/store_settings_edit_menu.dart';
import '../settings/store_settings_import_menu.dart';
import 'sign_in_options.dart';
import '../widgets/menu_filling.dart';
import 'entry_button.dart';
import 'account_fields.dart';
import 'entry_ui.dart';

// Path A — open a new store
// ---------------------------------------------------------------------------

/// Account → store name → menu, one question at a time.
///
/// The store id is never asked for and never shown. It is a generated
/// identifier that exists so documents have somewhere to live; the only thing
/// about the store anybody has to type is its name.
class OpenStoreRegistration extends StatefulWidget {
  const OpenStoreRegistration({this.account, super.key});

  /// An account that already exists and is signed in, for carrying on from a
  /// registration that stopped after it was created. The account step is
  /// skipped; everything after it is the same.
  final SignInResult? account;

  @override
  State<OpenStoreRegistration> createState() => _OpenStoreRegistrationState();
}

class _OpenStoreRegistrationState extends State<OpenStoreRegistration> {
  final _account = AccountFields();
  final _storeNameController = TextEditingController();

  final _pageController = PageController();
  int _step = 0;
  bool _submitting = false;
  String _storeNameError = '';

  /// Set once the store exists, which is also the point of no return: the last
  /// step is no longer part of registration, it is the first thing the owner
  /// does with a store that is already theirs.
  String? _createdStoreId;

  /// The account, when one already exists and is signed in.
  ///
  /// Two ways to get here. Google creates and signs in the account at the
  /// *account* step, whereas the form defers that to the store step. And a
  /// registration interrupted between those two points leaves an account
  /// behind with no documents, which this screen is also how somebody
  /// finishes. Either way it means the same thing to [_createStore]: do not
  /// try to create a second one.
  late SignInResult? _google = widget.account;

  /// The name to file the profile under, when the account has none of its own.
  ///
  /// A Google account always brings one. An interrupted email-and-password
  /// registration does not — `register()` only creates the sign-in — so the
  /// name it never got to write has to be asked for again.
  final _resumeNameController = TextEditingController();
  String _resumeNameError = '';

  @override
  void dispose() {
    // Backing out after signing in with Google, before the store exists, would
    // otherwise leave an account that can sign in and find nothing belonging to
    // it — and that then blocks the next attempt with "email already in use".
    // Best-effort and unawaited: this widget is going away either way, and the
    // alternative to a failed cleanup is no cleanup.
    _discardAbandonedGoogleAccount();

    _account.dispose();
    _resumeNameController.dispose();
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
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_submitting) _back();
      },
      child: Scaffold(
        appBar: buildEntryAppBar(
          context,
          onBack: _step == 0 ? null : (_submitting ? () {} : _back),
        ),
        body: SafeArea(
          child: Column(
            children: [
              StepDots(count: 3, current: _step),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_accountStep(), _storeStep(), _menuStep()],
                ),
              ),
            ],
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
      final resuming = widget.account != null;
      return StepBody(
        title: 'Your account',
        subtitle: resuming
            ? 'This account exists already. It just has no shop yet.'
            : 'Signed in with Google.',
        children: [
          SignedInBanner(result: google),
          if (google.displayName.isEmpty) ...[
            const SizedBox(height: 16),
            LabelledField(
              label: 'Your name',
              controller: _resumeNameController,
              errorText: _resumeNameError,
              helperText: 'Shown on the staff list and against orders you take',
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.name],
              onSubmitted: (_) => _next(),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _submitting ? null : _useDifferentAccount,
              child: Text(resuming
                  ? 'Not you? Sign out'
                  : 'Not you? Use a different account'),
            ),
          ),
          const SizedBox(height: 16),
          EntryButton(
            label: 'Continue',
            onPressed: _submitting ? null : _next,
          ),
        ],
      );
    }

    return StepBody(
      title: 'Your account',
      subtitle: 'This is how you sign in.',
      children: [
        _account.build(onSubmit: _next),
        const SizedBox(height: 8),
        EntryButton(label: 'Continue', onPressed: _submitting ? null : _next),
        const SizedBox(height: 24),
        SignInOptions(busy: _submitting, onGoogle: _continueWithGoogle),
      ],
    );
  }

  Widget _storeStep() => StepBody(
    title: 'Your store',
    subtitle: 'You can change this later in Store Settings.',
    children: [
      LabelledField(
        label: 'Store name',
        controller: _storeNameController,
        errorText: _storeNameError,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _next(),
      ),
      const SizedBox(height: 8),
      EntryButton(
        label: 'Create store',
        busy: _submitting,
        onPressed: _submitting ? null : _next,
      ),
      const SizedBox(height: 16),
      const StepNote(
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
  Widget _menuStep() => StepBody(
    title: 'Your store is ready',
    subtitle: 'The menu is empty. Nothing can be rung up until it is not.',
    children: [
      // The step said the menu was empty and offered three ways to fix it,
      // without ever showing what was being offered. This does.
      const SizedBox(height: 150, child: Center(child: MenuFilling())),
      const SizedBox(height: 24),
      EntryButton(
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
      const StepNote(
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
      await _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } on AuthException catch (e) {
      if (e.failure == AuthFailure.cancelled) return;
      if (mounted && !_account.showAuthError(e)) {
        showEntryError(context, e.message);
      }
    }
  }

  /// The name for an account that already exists: its own if it has one, and
  /// otherwise whatever was typed on the account step.
  String get _resumedName {
    final own = _google?.displayName.trim() ?? '';
    return own.isNotEmpty ? own : _resumeNameController.text.trim();
  }

  Future<void> _createStore() async {
    final storeName = _storeNameController.text.trim();
    setState(
      () => _storeNameError = storeName.isEmpty ? 'Enter the store name' : '',
    );
    if (_google != null && _resumedName.isEmpty) {
      setState(() {
        _resumeNameError = 'Enter your name';
        _step = 0;
      });
      await _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    if (storeName.isNotEmpty && _google == null && !_account.validate()) {
      // Something on the first step no longer passes — send them back to it
      // rather than failing against Firebase with a message they cannot act on.
      setState(() => _step = 0);
      await _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
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
      await userRepository.create(
        AppUser(
          uid: uid,
          email: email,
          displayName: google == null ? _account.displayName : _resumedName,
          storeId: storeId,
          role: UserRole.owner,
        ),
      );

      // No categories and no seeded dishes. An empty menu is honest.
      await storeRepository.create(Store(id: storeId, name: storeName));

      if (!mounted) return;
      setState(() {
        _createdStoreId = storeId;
        _step = 2;
      });
      await _pageController.animateToPage(
        2,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      // Every auth failure here is about a field on the first step.
      setState(() => _step = 0);
      await _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      if (mounted && !_account.showAuthError(e)) {
        showEntryError(context, e.message);
      }
    } catch (e) {
      // The sign-in account exists but its store does not, which would leave an
      // account that can sign in and then find nothing belonging to it.
      if (uid != null && accountIsNew) {
        await authRepository.deleteCurrentAccount();
        if (mounted) setState(() => _google = null);
      }
      if (mounted) {
        showEntryError(context, 'Could not create the store: $e');
      }
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
      navigator.push(
        MaterialPageRoute(builder: (_) => StoreImportMenu(storeId)),
      );
    }
  }
}

/// Where somebody is sent once their store exists.
enum _MenuStart { importFromPhoto, addByHand, later }
