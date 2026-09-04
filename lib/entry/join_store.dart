// Split out of lib/register.dart, which had grown to 1326 lines — the largest
// UI file in the project — by carrying the chooser, both registration flows and
// every piece of furniture they share in one place.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/repositories.dart';
import '../models/invite.dart';
import 'sign_in_options.dart';
import 'entry_button.dart';
import 'account_fields.dart';
import 'entry_ui.dart';

// ---------------------------------------------------------------------------
// Path B — join an existing store
// ---------------------------------------------------------------------------

/// Invite code first, account second.
///
/// The order is the whole point: nobody should fill in a page and only then
/// discover they typed the code wrong. On a good code the next screen names
/// the store, so joining the wrong one is caught before an account exists.
class JoinStoreRegistration extends StatefulWidget {
  const JoinStoreRegistration({this.account, super.key});

  /// An account that already exists and is signed in, for carrying on from a
  /// registration that stopped after it was created. The code step is the
  /// same; the account step becomes "you, joining", with no sign-up on it.
  final SignInResult? account;

  @override
  State<JoinStoreRegistration> createState() => _JoinStoreRegistrationState();
}

class _JoinStoreRegistrationState extends State<JoinStoreRegistration> {
  final _account = AccountFields();
  final _codeController = TextEditingController();

  final _pageController = PageController();
  int _step = 0;
  bool _submitting = false;
  String _codeError = '';

  /// The validated invite. Holding it is what lets the account step name the
  /// store — the person does not belong to it yet and so cannot read it.
  Invite? _invite;

  /// The name to redeem under, when the account has none of its own. An
  /// interrupted email-and-password registration leaves a sign-in with no
  /// display name, because that only ever lived in the profile it never wrote.
  final _resumeNameController = TextEditingController();
  String _resumeNameError = '';

  String get _resumedName {
    final own = widget.account?.displayName.trim() ?? '';
    return own.isNotEmpty ? own : _resumeNameController.text.trim();
  }

  @override
  void dispose() {
    _account.dispose();
    _resumeNameController.dispose();
    _codeController.dispose();
    _pageController.dispose();
    super.dispose();
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
              StepDots(count: 2, current: _step),
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
    );
  }

  Widget _codeStep() => StepBody(
    title: 'Your invite code',
    subtitle:
        'Six characters, from whoever manages the store. Codes work once '
        'and expire after 30 minutes.',
    children: [
      LabelledField(
        label: 'Invite code',
        controller: _codeController,
        errorText: _codeError,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
        inputFormatters: [
          // Order matters: strip the separators first, then cap. A limiter
          // running first would count the spaces in a pasted "abc - 234"
          // and truncate real characters off the end.
          InviteCodeFormatter(),
          LengthLimitingTextInputFormatter(Invite.codeLength),
        ],
        onSubmitted: (_) => _checkCode(),
      ),
      const SizedBox(height: 8),
      EntryButton(
        label: 'Check code',
        busy: _submitting,
        onPressed: _submitting ? null : _checkCode,
      ),
    ],
  );

  Widget _accountStep() {
    final invite = _invite;
    final resuming = widget.account;

    // An account that already exists has nothing to sign up for. The step
    // becomes the invite, a name if it never got one, and the button.
    if (resuming != null) {
      return StepBody(
        title: 'Your account',
        subtitle: 'This account exists already. It just has no shop yet.',
        children: [
          if (invite != null) ...[
            JoiningBanner(invite: invite),
            const SizedBox(height: 24),
          ],
          SignedInBanner(result: resuming),
          if (resuming.displayName.isEmpty) ...[
            const SizedBox(height: 16),
            LabelledField(
              label: 'Your name',
              controller: _resumeNameController,
              errorText: _resumeNameError,
              helperText: 'Shown on the staff list and against orders you take',
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.name],
              onSubmitted: (_) => _joinAsExisting(),
            ),
          ],
          const SizedBox(height: 16),
          EntryButton(
            label: 'Join store',
            busy: _submitting,
            onPressed: _submitting ? null : _joinAsExisting,
          ),
        ],
      );
    }

    return StepBody(
      title: 'Your account',
      subtitle: 'This is how you sign in.',
      children: [
        if (invite != null) ...[
          JoiningBanner(invite: invite),
          const SizedBox(height: 24),
        ],
        _account.build(onSubmit: _join),
        const SizedBox(height: 8),
        EntryButton(
          label: 'Join store',
          busy: _submitting,
          onPressed: _submitting ? null : _join,
        ),
        const SizedBox(height: 24),
        SignInOptions(busy: _submitting, onGoogle: _joinWithGoogle),
      ],
    );
  }

  /// Redeems the code for an account that already exists.
  ///
  /// No account is created and none is deleted on failure — this one was not
  /// brought into existence here, and taking it away would leave somebody with
  /// neither a shop nor a sign-in.
  Future<void> _joinAsExisting() async {
    final account = widget.account;
    final invite = _invite;
    if (account == null || _submitting) return;
    if (invite == null) return _back();

    if (_resumedName.isEmpty) {
      setState(() => _resumeNameError = 'Enter your name');
      return;
    }

    setState(() => _submitting = true);
    try {
      await inviteRepository.redeem(
        code: invite.code,
        uid: account.uid,
        email: account.email,
        displayName: _resumedName,
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on InviteException catch (e) {
      if (!mounted) return;
      setState(() {
        _codeError = e.message;
        _step = 0;
        _invite = null;
      });
      await _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } catch (e) {
      if (mounted) {
        showEntryError(
          context,
          'Could not join the store. ${describeFailure(e).message}',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
          showEntryError(
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
        showEntryError(context, e.message);
      }
    } on InviteException catch (e) {
      await _undo(account);
      if (!mounted) return;
      setState(() {
        _codeError = e.message;
        _step = 0;
        _invite = null;
      });
      await _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } catch (e) {
      await _undo(account);
      if (mounted) {
        // Translated rather than interpolated: `$e` on a Firestore failure
        // opens with `[cloud_firestore/permission-denied]`, which is an error
        // code shown to somebody halfway through joining a shop.
        showEntryError(
          context,
          'Could not join the store. ${describeFailure(e).message}',
        );
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
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _checkCode() async {
    if (_submitting) return;
    final typed = Invite.normalise(_codeController.text);
    setState(
      () => _codeError = Invite.isWellFormed(typed)
          ? ''
          : 'An invite code is ${Invite.codeLength} characters',
    );
    if (_codeError.isNotEmpty) return;

    setState(() => _submitting = true);
    try {
      final invite = await inviteRepository.validate(typed);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _step = 1;
      });
      await _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
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
        showEntryError(context, e.message);
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
      await _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } catch (e) {
      if (uid != null) await authRepository.deleteCurrentAccount();
      if (mounted) {
        showEntryError(context, 'Could not join the store: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
