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
  "android:apk-key-hash:zRuSX88IxxAfUr1ZXMHSW2ZqWJDjXeynpD3q0M3WRrg",
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
