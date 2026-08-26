import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Why an authentication call failed, in terms the app cares about.
///
/// Screens need to react differently to different failures — registration
/// puts "password too short" under the password field and "email already
/// taken" under the email field — so a single message string is not enough.
/// This enum is the part of a failure a screen may branch on; [AuthException]
/// carries wording for everything else.
enum AuthFailure {
  wrongPassword,
  invalidEmail,
  emailInUse,
  weakPassword,
  userDisabled,
  /// Email/password sign-in is switched off in the Firebase console.
  signInMethodDisabled,
  networkUnavailable,
  /// The account must sign in again before this operation is allowed.
  reauthenticationRequired,

  /// The person closed the Google or passkey sheet without finishing.
  cancelled,

  /// The email already has an account created a different way, and the
  /// project's account-linking setting will not merge them.
  credentialConflict,
  unknown,
}

/// What a sign-in produced, beyond the uid.
///
/// Google hands back a name and an email that registration would otherwise
/// have had to ask for, and [isNewAccount] is what tells a caller whether this
/// person still needs a store attached to them.
class SignInResult {
  const SignInResult({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.isNewAccount = false,
  });

  final String uid;
  final String email;
  final String displayName;

  /// True when Firebase created the account during this call rather than
  /// finding an existing one.
  final bool isNewAccount;
}

/// An authentication failure, already translated out of Firebase's vocabulary.
class AuthException implements Exception {
  const AuthException(this.failure, this.message);

  final AuthFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// Everything that touches Firebase Authentication.
///
/// This is the only place in the app allowed to import `firebase_auth`. Screens
/// deal in uids, emails and [AuthException]; the `User` and
/// `FirebaseAuthException` types never reach them. That is what keeps the
/// sign-in provider replaceable, and it is why the error wording lives here
/// rather than being re-invented by each screen that calls in.
class AuthRepository {
  AuthRepository({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// The signed-in uid, or null while signed out.
  String? get currentUid => _auth.currentUser?.uid;

  String? get currentEmail => _auth.currentUser?.email;

  /// Emits the signed-in uid, and null on sign-out.
  ///
  /// Deliberately not a `User`: the root of the app only needs to know whether
  /// somebody is signed in and who they are.
  Stream<String?> get uidChanges =>
      _auth.authStateChanges().map((user) => user?.uid);

  /// Signs in and returns the uid.
  Future<String> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user!.uid;
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    }
  }

  /// Creates an account and returns its uid.
  ///
  /// The new account is signed in immediately, before it has any Firestore
  /// documents. The caller is responsible for provisioning those and for
  /// calling [deleteCurrentAccount] if that provisioning fails.
  Future<String> register({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user!.uid;
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    }
  }

  // ------------------------------------------------------------------
  // Google
  // ------------------------------------------------------------------

  /// Whether a Google button is worth showing at all.
  ///
  /// Web goes through Firebase's own popup; Android goes through
  /// `google_sign_in`. Windows has neither, and a button that can only fail is
  /// worse than no button.
  /// Uses [defaultTargetPlatform] rather than `dart:io`'s `Platform`, which
  /// does not exist on web and would take the whole web build down with it.
  bool get supportsGoogle {
    if (kIsWeb) return true;
    return const {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);
  }

  /// Signs in with Google and returns the uid, plus the name and email Google
  /// already knows — which is three fields registration no longer has to ask
  /// for.
  ///
  /// Two implementations behind one method, because the platforms genuinely
  /// differ. `google_sign_in_web` reports `supportsAuthenticate() == false` and
  /// throws if you call `authenticate()`; it only offers a Google-rendered
  /// button widget. Firebase's own `signInWithPopup` has no such restriction
  /// and needs no client id in `index.html`, so web uses that instead.
  Future<SignInResult> signInWithGoogle() async {
    try {
      final credential =
          kIsWeb ? await _googlePopup() : await _googleNative();
      return _describe(credential);
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    } on GoogleSignInException catch (e) {
      throw _translateGoogle(e);
    }
  }

  Future<UserCredential> _googlePopup() =>
      _auth.signInWithPopup(GoogleAuthProvider());

  Future<UserCredential> _googleNative() async {
    final google = GoogleSignIn.instance;

    // Safe to call more than once; the plugin treats a repeat as a no-op. No
    // clientId is passed: on Android the ids come from google-services.json,
    // and hard-coding them here would be a second place to keep in step.
    await google.initialize();

    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException(
        AuthFailure.unknown,
        'Google did not return an ID token. Check that this app\'s signing '
        'SHA-1 is registered in the Firebase console and that '
        'google-services.json is up to date.',
      );
    }

    return _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  // ------------------------------------------------------------------
  // Custom tokens (passkeys)
  // ------------------------------------------------------------------

  /// Completes a passkey sign-in with the token the relying party minted.
  ///
  /// Firebase Authentication has no passkey provider, so a verified WebAuthn
  /// assertion is turned into a session the only way it can be: a Cloud
  /// Function holding the service account key signs a custom token for the uid,
  /// and this exchanges it. See `functions/src/passkeys.ts`.
  Future<SignInResult> signInWithCustomToken(String token) async {
    try {
      return _describe(await _auth.signInWithCustomToken(token));
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    }
  }

  SignInResult _describe(UserCredential credential) {
    final user = credential.user!;
    return SignInResult(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
      isNewAccount: credential.additionalUserInfo?.isNewUser ?? false,
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// Removes the signed-in account. Used to undo a registration whose
  /// Firestore side failed, which would otherwise leave an account that can
  /// sign in and then find nothing belonging to it.
  ///
  /// Best-effort on purpose: if the deletion itself fails there is nothing
  /// useful left to do, and the original failure is the one worth reporting.
  Future<void> deleteCurrentAccount() async {
    try {
      await _auth.currentUser?.delete();
    } catch (_) {
      // Swallowed deliberately — see above.
    }
  }

  /// Re-authenticates with the current password, then sets a new one.
  ///
  /// The email comes from the signed-in account rather than from the caller:
  /// re-authentication has to use the address the account actually has, and a
  /// value passed down through screens can be stale.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AuthException(
        AuthFailure.reauthenticationRequired,
        'You are not signed in with an email and password.',
      );
    }

    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    }
  }

  /// Maps a `google_sign_in` failure onto an [AuthException].
  ///
  /// Cancelling is not an error worth a red snackbar — the caller is expected
  /// to branch on [AuthFailure.cancelled] and stay quiet.
  AuthException _translateGoogle(GoogleSignInException e) =>
      switch (e.code) {
        GoogleSignInExceptionCode.canceled ||
        GoogleSignInExceptionCode.interrupted =>
          const AuthException(
            AuthFailure.cancelled,
            'Google sign-in was cancelled.',
          ),
        GoogleSignInExceptionCode.providerConfigurationError =>
          const AuthException(
            AuthFailure.signInMethodDisabled,
            'Google sign-in is not configured for this app. Check the OAuth '
                'client and the signing SHA-1 in the Firebase console.',
          ),
        _ => AuthException(
            AuthFailure.unknown,
            e.description ?? 'Google sign-in failed (${e.code.name}).',
          ),
      };

  /// Maps a Firebase error code onto an [AuthException].
  ///
  /// `invalid-credential` is what recent Firebase versions return instead of
  /// `wrong-password` / `user-not-found`; both spellings are handled because
  /// which one arrives depends on the project's email-enumeration setting.
  AuthException _translate(FirebaseAuthException e) => switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          const AuthException(
            AuthFailure.wrongPassword,
            'Wrong email or password.',
          ),
        'invalid-email' => const AuthException(
            AuthFailure.invalidEmail,
            'That is not a valid email address.',
          ),
        'email-already-in-use' => const AuthException(
            AuthFailure.emailInUse,
            'An account already exists for that email.',
          ),
        'weak-password' => const AuthException(
            AuthFailure.weakPassword,
            'The password must be at least 6 characters.',
          ),
        'user-disabled' => const AuthException(
            AuthFailure.userDisabled,
            'This account has been disabled.',
          ),
        'operation-not-allowed' => const AuthException(
            AuthFailure.signInMethodDisabled,
            'Email/password sign-in is not enabled for this Firebase project. '
                'Enable it under Authentication → Sign-in method.',
          ),
        'network-request-failed' => const AuthException(
            AuthFailure.networkUnavailable,
            'No connection to Firebase. Check your network.',
          ),
        'requires-recent-login' => const AuthException(
            AuthFailure.reauthenticationRequired,
            'Please sign out and sign in again before changing this.',
          ),
        'account-exists-with-different-credential' => const AuthException(
            AuthFailure.credentialConflict,
            'That email already has an account created a different way. Sign '
                'in with the original method first.',
          ),
        'popup-closed-by-user' || 'cancelled-popup-request' =>
          const AuthException(
            AuthFailure.cancelled,
            'Google sign-in was cancelled.',
          ),
        'invalid-custom-token' || 'custom-token-mismatch' =>
          const AuthException(
            AuthFailure.unknown,
            'The passkey sign-in token was rejected. Please try again.',
          ),
        // Anything unhandled still says what happened. Registration used to
        // fail silently here: the button stopped spinning and nothing on
        // screen explained why.
        _ => AuthException(
            AuthFailure.unknown,
            e.message ?? 'Authentication failed (${e.code}).',
          ),
      };
}
