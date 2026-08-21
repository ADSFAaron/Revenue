import 'package:firebase_auth/firebase_auth.dart';

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
  unknown,
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
        // Anything unhandled still says what happened. Registration used to
        // fail silently here: the button stopped spinning and nothing on
        // screen explained why.
        _ => AuthException(
            AuthFailure.unknown,
            e.message ?? 'Authentication failed (${e.code}).',
          ),
      };
}
