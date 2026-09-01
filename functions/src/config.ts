/**
 * The handful of values that tie this relying party to one app on one domain.
 *
 * Everything here is a deployment fact rather than a secret — the RP ID is
 * public by definition, and the Android hash is derived from a signing
 * certificate whose fingerprint anyone can read off an installed APK.
 */

/**
 * The WebAuthn Relying Party ID: the domain a passkey is bound to.
 *
 * This is the single most consequential value in the file. A passkey created
 * against one RP ID cannot be used against another, so changing it invalidates
 * every passkey anybody has already registered. If the app moves to a custom
 * domain, that is a migration, not a config edit.
 */
export const RP_ID = "revenueapp-b8849.web.app";

/** Shown by the authenticator's own UI when it asks the person to confirm. */
export const RP_NAME = "Revenue";

/**
 * Taiwan. The store is in Taiwan and its staff sign in from there; a login
 * round trip to us-central1 and back is roughly a fifth of a second of nothing
 * happening. Cloud Run functions (2nd gen) are available in this region.
 *
 * The Dart side has to agree — see `passkeyFunctionsRegion` in
 * lib/database/passkey_repository.dart.
 */
export const REGION = "asia-east1";

/**
 * Every function is capped. An unbounded function is the thing that actually
 * produces a surprise bill: a runaway loop or a burst of traffic can otherwise
 * scale to hundreds of instances. Six sign-ins happening at once is already
 * more than this app will ever see.
 */
export const MAX_INSTANCES = 3;

/**
 * Where a WebAuthn ceremony is allowed to have come from.
 *
 * Web sends the page origin. Android does not — the Credential Manager sends
 * `android:apk-key-hash:<base64url of the SHA-256 of the signing certificate>`,
 * which is a completely different shape and has to be listed explicitly or
 * every Android assertion is rejected.
 *
 * The hash below is the **debug** signing certificate, because
 * android/app/build.gradle currently signs release builds with it
 * (`signingConfig signingConfigs.debug`). When a real release keystore
 * arrives, this and web/well-known/assetlinks.json both need its fingerprint
 * instead — they are two encodings of the same SHA-256 and must never
 * disagree.
 *
 *   keytool -list -v -keystore <keystore> -alias <alias> \
 *     | grep SHA256          # colon-separated hex, for assetlinks.json
 *
 * The value here is that same hash, base64url-encoded without padding.
 */
export const EXPECTED_ORIGINS = [
  `https://${RP_ID}`,
  // Debug keystore. Kept so passkeys work in `flutter run` on this machine.
  "android:apk-key-hash:zRuSX88IxxAfUr1ZXMHSW2ZqWJDjXeynpD3q0M3WRrg",
  // Upload keystore (~/upload-keystore.jks, alias `upload`), SHA-256
  // 05:A6:DB:61:…:D4:32. This is what signs a locally built release AAB, so it
  // covers a build sideloaded for testing before it reaches Play.
  "android:apk-key-hash:BabbYYihmNAgv-C110ApNuQNHMjbMwPFwrTy92jP1DI",
  // TODO — Google's Play App Signing certificate. Play re-signs every upload,
  // so the hash an installed-from-Play build actually presents is Google's and
  // is none of the three above. It does not exist until the first upload has
  // been made; take it from Play Console → Release → Setup → App signing and
  // add it here and to web/well-known/assetlinks.json, or Android passkeys
  // fail with `domain-not-associated` for every real user while working
  // perfectly on this machine.
];

/**
 * How long a challenge stays usable.
 *
 * Short on purpose: a challenge is the only thing standing between a captured
 * assertion and a replay of it, so it is single-use *and* short-lived. Sixty
 * seconds is comfortably longer than a Face ID prompt takes and far shorter
 * than any useful attack window.
 */
export const CHALLENGE_TTL_MS = 60_000;

/** `passkeyCredentials/{credentialId}` — public keys, keyed by credential id. */
export const CREDENTIALS = "passkeyCredentials";

/** `passkeyChallenges/{challengeId}` — single-use, 60-second lifetime. */
export const CHALLENGES = "passkeyChallenges";

/**
 * The options every callable in this project shares.
 *
 * `enforceAppCheck` is the important one, and it was missing. The app has
 * activated App Check since it was added to `configureAppCheck` in
 * lib/database/repositories.dart — Play Integrity on Android, reCAPTCHA
 * Enterprise on web — so every real call has carried an attestation token for
 * some time. Nothing on this side ever looked at it, which meant the token
 * proved nothing: `curl` with a Firebase ID token reached exactly the same
 * endpoints, and `importMenuFromPhotos` is the one call here that spends real
 * money on every invocation.
 *
 * The comment at the top of quota.ts already said this in as many words —
 * that the role check "protects a shop from its own staff. It does not protect
 * the project from a stranger." App Check is what protects it from the
 * stranger, and it only does so once it is enforced.
 *
 * Two consequences to know about before deploying:
 *
 *   * **Web must be built with the reCAPTCHA site key.** `configureAppCheck`
 *     returns early on web when `APP_CHECK_RECAPTCHA_KEY` is empty, so a web
 *     build made without `--dart-define=APP_CHECK_RECAPTCHA_KEY=<key>` sends
 *     no token and every callable now refuses it. That build is already
 *     documented; this is what makes forgetting it a hard failure rather than
 *     a quiet one.
 *
 *   * **Debug builds need a registered debug token.** Android debug runs use
 *     `AndroidProvider.debug`, whose token has to be pasted into the Firebase
 *     console (App Check → Apps → Manage debug tokens) once per machine.
 *
 * Both are the intended behaviour of enforcement, not side effects of it: the
 * point is that a caller which cannot prove it is this app does not get in.
 */
export const CALLABLE_OPTIONS = {
  region: REGION,
  maxInstances: MAX_INSTANCES,
  enforceAppCheck: true,
} as const;
