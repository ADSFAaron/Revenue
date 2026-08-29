import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import 'auth_repository.dart';
import 'data_exception.dart';

/// Which region the relying party is deployed to.
///
/// Must match `REGION` in functions/src/config.ts. Getting this wrong does not
/// fail at build time — it fails at call time with a bare "not found", because
/// a callable is addressed by region and name together.
const String passkeyFunctionsRegion = 'asia-east1';

/// One of the caller's registered passkeys, as the manage screen sees it.
///
/// Metadata only. The public key and signature counter never leave the server;
/// nothing in the app has any use for them, and a client that could read them
/// is a client that could be asked to leak them.
class PasskeyInfo {
  const PasskeyInfo({
    required this.credentialId,
    required this.deviceName,
    this.createdAt,
    this.lastUsedAt,
  });

  final String credentialId;

  /// What the person called this device when they added it, so they can tell
  /// which of their phones a credential belongs to.
  final String deviceName;

  final DateTime? createdAt;
  final DateTime? lastUsedAt;
}

/// Why a passkey operation failed, in terms a screen can act on.
enum PasskeyFailure {
  /// The sheet was dismissed. Not an error worth a red snackbar.
  cancelled,

  /// This device or browser cannot do passkeys at all.
  unsupported,

  /// The app is not associated with the relying party's domain — on Android,
  /// `/.well-known/assetlinks.json` is missing, unreachable, or carries the
  /// wrong signing fingerprint.
  domainNotAssociated,

  /// The account already has a passkey on this authenticator.
  alreadyRegistered,

  /// Nothing on this device matches; there is no passkey to sign in with.
  noCredentials,

  /// The challenge expired or the assertion did not verify.
  rejected,

  unknown,
}

class PasskeyException implements AppException {
  const PasskeyException(this.failure, this.message);

  final PasskeyFailure failure;

  @override
  final String message;

  @override
  String toString() => message;
}

/// The client half of the WebAuthn ceremony.
///
/// The `passkeys` package signs challenges and verifies nothing; every check
/// that matters happens in functions/src/passkeys.ts. This class is the wire
/// between the two, and it is the only place in the app that knows either
/// exists.
///
/// A passkey is always additive. It is attached to an account somebody can
/// already reach, and email and password keep working forever — losing a phone
/// must not lock an owner out of their own books.
class PasskeyRepository {
  PasskeyRepository({
    PasskeyAuthenticator? authenticator,
    FirebaseFunctions? functions,
    AuthRepository? auth,
  })  : _authenticator = authenticator ?? PasskeyAuthenticator(),
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: passkeyFunctionsRegion),
        _auth = auth ?? AuthRepository();

  final PasskeyAuthenticator _authenticator;
  final FirebaseFunctions _functions;
  final AuthRepository _auth;

  /// Whether to offer passkeys on this device at all.
  ///
  /// Checked rather than assumed: Android below API 28 has no passkey APIs, a
  /// browser may be too old, and a button that can only fail is worse than no
  /// button. Any failure to answer is treated as "no" — this is a nicety, and
  /// it must never be the thing that breaks a login screen.
  Future<bool> isSupported() async {
    try {
      if (kIsWeb) {
        return (await _authenticator.getAvailability().web()).hasPasskeySupport;
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        return (await _authenticator.getAvailability().android())
            .hasPasskeySupport;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return (await _authenticator.getAvailability().iOS()).hasPasskeySupport;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Adds a passkey to the signed-in account. Returns the name it was stored
  /// under.
  Future<String> add({String? deviceName}) async {
    final begin = await _call('beginPasskeyRegistration');
    final challengeId = begin['challengeId'] as String;

    final RegisterResponseType signed;
    try {
      signed = await _authenticator.register(
        RegisterRequestType.fromJson(_asMap(begin['options'])),
      );
    } catch (e) {
      throw _translateAuthenticator(e);
    }

    final finish = await _call('finishPasskeyRegistration', {
      'challengeId': challengeId,
      'response': signed.toJson(),
      'deviceName': deviceName ?? defaultDeviceName,
    });
    return finish['deviceName'] as String? ?? (deviceName ?? 'This device');
  }

  /// Signs in with a passkey and returns who was signed in.
  ///
  /// No email is asked for and none is sent. The credential is discoverable,
  /// so the authenticator shows the person their own passkeys and tells the
  /// server which one they chose; the server resolves that to a uid. That also
  /// means this flow cannot be used to ask whether a given email has an
  /// account, because it is never told one.
  Future<SignInResult> signIn() async {
    final begin = await _call('beginPasskeyAuthentication');
    final challengeId = begin['challengeId'] as String;

    final AuthenticateResponseType signed;
    try {
      signed = await _authenticator.authenticate(
        AuthenticateRequestType.fromJson(
          _asMap(begin['options']),
          preferImmediatelyAvailableCredentials: false,
        ),
      );
    } catch (e) {
      throw _translateAuthenticator(e);
    }

    final finish = await _call('finishPasskeyAuthentication', {
      'challengeId': challengeId,
      'response': signed.toJson(),
    });

    final token = finish['token'] as String?;
    if (token == null) {
      throw const PasskeyException(
        PasskeyFailure.rejected,
        'The passkey was not accepted. Please try again.',
      );
    }

    try {
      return await _auth.signInWithCustomToken(token);
    } on AuthException catch (e) {
      throw PasskeyException(PasskeyFailure.rejected, e.message);
    }
  }

  /// The caller's own passkeys. Goes through a callable rather than a query
  /// because `passkeyCredentials` denies the client every kind of access.
  Future<List<PasskeyInfo>> list() async {
    final result = await _call('listPasskeys');
    final rows = result['passkeys'] as List<Object?>? ?? const [];
    return rows.map((row) {
      final data = _asMap(row);
      return PasskeyInfo(
        credentialId: data['credentialId'] as String? ?? '',
        deviceName: data['deviceName'] as String? ?? 'Unnamed device',
        createdAt: _millis(data['createdAt']),
        lastUsedAt: _millis(data['lastUsedAt']),
      );
    }).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(1970))
          .compareTo(a.createdAt ?? DateTime(1970)));
  }

  Future<void> remove(String credentialId) =>
      _call('deletePasskey', {'credentialId': credentialId});

  /// A first guess at what to call this device, so the add dialog has
  /// something in the field rather than an empty box.
  String get defaultDeviceName {
    if (kIsWeb) return 'This browser';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android phone',
      TargetPlatform.iOS => 'iPhone',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows PC',
      _ => 'This device',
    };
  }

  Future<Map<String, dynamic>> _call(
    String name, [
    Map<String, dynamic>? payload,
  ]) async {
    try {
      final result = await _functions.httpsCallable(name).call(payload);
      return _asMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      throw _translateFunctions(e);
    }
  }

  /// Callables hand back `Map<Object?, Object?>` on Android, and a plain
  /// `Map<String, dynamic>` on web. Everything downstream — including
  /// `RegisterRequestType.fromJson` — wants the latter, and a shallow cast is
  /// not enough because WebAuthn options nest three deep.
  static Map<String, dynamic> _asMap(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, item) => MapEntry('$key', _deepen(item)));
  }

  static Object? _deepen(Object? value) {
    if (value is Map) return _asMap(value);
    if (value is List) return value.map(_deepen).toList();
    return value;
  }

  static DateTime? _millis(Object? value) => value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
      : null;

  /// Turns the platform authenticator's vocabulary into this app's.
  ///
  /// `domain-not-associated` is the one worth naming precisely: on Android it
  /// means `/.well-known/assetlinks.json` is missing, unreachable, or lists a
  /// signing fingerprint that is not the one this build was signed with. It is
  /// by far the most common way a correct implementation still fails.
  PasskeyException _translateAuthenticator(Object error) => switch (error) {
        PasskeyAuthCancelledException() => const PasskeyException(
            PasskeyFailure.cancelled,
            'Cancelled.',
          ),
        NoCredentialsAvailableException() => const PasskeyException(
            PasskeyFailure.noCredentials,
            'No passkey on this device for Revenue. Sign in another way, then '
                'add one from Settings.',
          ),
        ExcludeCredentialsCanNotBeRegisteredException() => const PasskeyException(
            PasskeyFailure.alreadyRegistered,
            'This device already has a passkey for your account.',
          ),
        DomainNotAssociatedException() => const PasskeyException(
            PasskeyFailure.domainNotAssociated,
            'This app is not associated with the Revenue domain yet, so it '
                'cannot use passkeys. /.well-known/assetlinks.json needs to be '
                'published with this build\'s signing fingerprint.',
          ),
        PasskeyUnsupportedException() || DeviceNotSupportedException() =>
          const PasskeyException(
            PasskeyFailure.unsupported,
            'This device cannot use passkeys.',
          ),
        MissingGoogleSignInException() => const PasskeyException(
            PasskeyFailure.unsupported,
            'Add a Google account to this device before using passkeys.',
          ),
        SyncAccountNotAvailableException() => const PasskeyException(
            PasskeyFailure.unsupported,
            'Turn on a password-manager account on this device before using '
                'passkeys.',
          ),
        PasskeyException() => error,
        _ => PasskeyException(PasskeyFailure.unknown, '$error'),
      };

  PasskeyException _translateFunctions(FirebaseFunctionsException e) =>
      switch (e.code) {
        'unauthenticated' => PasskeyException(
            PasskeyFailure.rejected,
            e.message ?? 'That passkey is not recognised.',
          ),
        'failed-precondition' => PasskeyException(
            PasskeyFailure.rejected,
            e.message ?? 'That request has expired. Please try again.',
          ),
        'not-found' => const PasskeyException(
            PasskeyFailure.unknown,
            'The passkey service is not deployed. Run '
                '`firebase deploy --only functions`.',
          ),
        'unavailable' => const PasskeyException(
            PasskeyFailure.unknown,
            'Could not reach the passkey service. Check your network.',
          ),
        _ => PasskeyException(
            PasskeyFailure.unknown,
            e.message ?? 'The passkey service failed (${e.code}).',
          ),
      };
}
