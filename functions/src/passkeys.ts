/**
 * The WebAuthn relying party.
 *
 * Firebase Authentication has no passkey provider and `firebase_auth` has not
 * exposed one either, so a passkey cannot sign anybody in on its own. What it
 * can do is prove possession of a private key. This file is the half that
 * checks that proof and, having checked it, mints a Firebase custom token for
 * the uid the credential belongs to. Minting requires the service account key,
 * which is why this cannot live in the app.
 *
 * The client half is the `passkeys` Flutter package: it hands back signed data
 * and verifies nothing. Every check that matters happens here.
 *
 *   Adding a passkey        Signing in with one
 *   ------------------      -------------------
 *   beginRegistration       beginAuthentication
 *     → challenge (60s)       → challenge (60s)
 *   passkeys.register()     passkeys.authenticate()
 *     → attestation           → assertion
 *   finishRegistration      finishAuthentication
 *     → verify, store         → verify, then createCustomToken(uid)
 *                             → signInWithCustomToken
 */

import { getAuth } from "firebase-admin/auth";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall, CallableRequest } from "firebase-functions/v2/https";
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from "@simplewebauthn/server";
import type {
  AuthenticationResponseJSON,
  AuthenticatorTransportFuture,
  RegistrationResponseJSON,
} from "@simplewebauthn/server";

import {
  CHALLENGES,
  CHALLENGE_TTL_MS,
  CREDENTIALS,
  EXPECTED_ORIGINS,
  MAX_INSTANCES,
  REGION,
  RP_ID,
  RP_NAME,
} from "./config.js";

const options = { region: REGION, maxInstances: MAX_INSTANCES };

/** What a stored credential looks like in `passkeyCredentials/{credentialId}`. */
interface StoredCredential {
  uid: string;
  /** base64, because Firestore has no Uint8Array and this never gets queried. */
  publicKey: string;
  /**
   * Incremented by the authenticator on every use. A count that goes backwards
   * means the credential has been cloned; `verifyAuthenticationResponse`
   * rejects that for us, given the previous value.
   */
  signCount: number;
  transports: AuthenticatorTransportFuture[];
  deviceName: string;
}

const db = () => getFirestore();

// ---------------------------------------------------------------------------
// Adding a passkey
// ---------------------------------------------------------------------------

/**
 * Issues a registration challenge for the signed-in account.
 *
 * Sign-in is required and always will be: passkeys are additive here, never
 * the only way in. Losing a phone must not lock an owner out of their own
 * books, so a passkey is something you attach to an account you can already
 * reach, not something you bootstrap an account from.
 */
export const beginPasskeyRegistration = onCall(options, async (request) => {
  const uid = requireUid(request);
  const user = await getAuth().getUser(uid);

  const existing = await db()
    .collection(CREDENTIALS)
    .where("uid", "==", uid)
    .get();

  const created = await generateRegistrationOptions({
    rpName: RP_NAME,
    rpID: RP_ID,
    // The uid, so the authenticator hands it straight back as `userHandle` at
    // sign-in time. That is what makes a usernameless sign-in possible: there
    // is nobody to ask "who are you?" before the passkey has answered.
    userID: new Uint8Array(Buffer.from(uid, "utf8")),
    userName: user.email ?? uid,
    userDisplayName: user.displayName ?? user.email ?? "Revenue",
    // 'none' because nothing here cares which brand of authenticator this is,
    // and asking for attestation means handling a privacy prompt for no gain.
    attestationType: "none",
    // Registering the same authenticator twice would silently replace the
    // first credential. Listing what this account already has makes the
    // platform say "you already have a passkey here" instead.
    excludeCredentials: existing.docs.map((doc) => ({
      id: doc.id,
      transports: (doc.data() as StoredCredential).transports,
    })),
    authenticatorSelection: {
      // Discoverable, or sign-in cannot start from "who is this?".
      residentKey: "required",
      userVerification: "preferred",
    },
    // ES256 and RS256. Every platform authenticator worth supporting does one.
    supportedAlgorithmIDs: [-7, -257],
  });

  const challengeId = await storeChallenge(created.challenge, "registration", uid);
  return { challengeId, options: created };
});

/**
 * Verifies the attestation and stores the public key.
 */
export const finishPasskeyRegistration = onCall(options, async (request) => {
  const uid = requireUid(request);
  const { challengeId, response, deviceName } = request.data ?? {};
  requireString(challengeId, "challengeId");

  const challenge = await consumeChallenge(challengeId, "registration", uid);

  let verification;
  try {
    verification = await verifyRegistrationResponse({
      response: response as RegistrationResponseJSON,
      expectedChallenge: challenge,
      expectedOrigin: EXPECTED_ORIGINS,
      expectedRPID: RP_ID,
    });
  } catch (error) {
    throw new HttpsError("invalid-argument", describe(error));
  }

  if (!verification.verified || !verification.registrationInfo) {
    throw new HttpsError("invalid-argument", "The passkey could not be verified.");
  }

  const { credential } = verification.registrationInfo;
  const record: StoredCredential = {
    uid,
    publicKey: Buffer.from(credential.publicKey).toString("base64"),
    signCount: credential.counter,
    transports: credential.transports ?? [],
    deviceName: typeof deviceName === "string" && deviceName.trim()
      ? deviceName.trim().slice(0, 60)
      : "Unnamed device",
  };

  await db().collection(CREDENTIALS).doc(credential.id).set({
    ...record,
    createdAt: FieldValue.serverTimestamp(),
    lastUsedAt: null,
  });

  return { credentialId: credential.id, deviceName: record.deviceName };
});

// ---------------------------------------------------------------------------
// Signing in with a passkey
// ---------------------------------------------------------------------------

/**
 * Issues an authentication challenge. Deliberately unauthenticated — the whole
 * point is to sign somebody in who is not signed in yet.
 *
 * No `allowCredentials`: the credential is discoverable, so the authenticator
 * shows the person their own passkeys and tells us which one they picked. That
 * also means this endpoint reveals nothing. It cannot be used to ask "does
 * this email have a passkey?", because it is never told an email.
 */
export const beginPasskeyAuthentication = onCall(options, async () => {
  const created = await generateAuthenticationOptions({
    rpID: RP_ID,
    userVerification: "preferred",
  });

  const challengeId = await storeChallenge(created.challenge, "authentication");
  return { challengeId, options: created };
});

/**
 * Verifies the assertion and mints a Firebase custom token for the account the
 * credential belongs to.
 *
 * This is the only function that can hand out a session, so it is the one
 * worth reading twice. Six things are checked, and all six matter: the
 * challenge is one we issued, is unspent and has not expired; the origin is
 * one of ours; the RP ID matches; the signature verifies against the stored
 * public key; and the signature counter has not gone backwards.
 */
export const finishPasskeyAuthentication = onCall(options, async (request) => {
  const { challengeId, response } = request.data ?? {};
  requireString(challengeId, "challengeId");

  const assertion = response as AuthenticationResponseJSON;
  if (!assertion?.id) {
    throw new HttpsError("invalid-argument", "No credential in the response.");
  }

  const challenge = await consumeChallenge(challengeId, "authentication");

  const doc = await db().collection(CREDENTIALS).doc(assertion.id).get();
  if (!doc.exists) {
    // Same wording as a failed signature on purpose: distinguishing "unknown
    // credential" from "bad signature" tells a prober which of their guesses
    // exists.
    throw new HttpsError("unauthenticated", "That passkey is not recognised.");
  }
  const stored = doc.data() as StoredCredential;

  let verification;
  try {
    verification = await verifyAuthenticationResponse({
      response: assertion,
      expectedChallenge: challenge,
      expectedOrigin: EXPECTED_ORIGINS,
      expectedRPID: RP_ID,
      credential: {
        id: doc.id,
        publicKey: new Uint8Array(Buffer.from(stored.publicKey, "base64")),
        counter: stored.signCount,
        transports: stored.transports,
      },
    });
  } catch (error) {
    throw new HttpsError("unauthenticated", describe(error));
  }

  if (!verification.verified) {
    throw new HttpsError("unauthenticated", "That passkey is not recognised.");
  }

  await doc.ref.update({
    signCount: verification.authenticationInfo.newCounter,
    lastUsedAt: FieldValue.serverTimestamp(),
  });

  return { token: await getAuth().createCustomToken(stored.uid) };
});

// ---------------------------------------------------------------------------
// Managing them
// ---------------------------------------------------------------------------

/**
 * The caller's own passkeys, metadata only.
 *
 * Goes through a function rather than a Firestore query because the rules deny
 * the client every kind of access to `passkeyCredentials`. Public keys and
 * sign counters are the security-critical half of WebAuthn, and the client has
 * no business reading either — so the collection stays closed and this returns
 * only what a person needs to recognise their own devices.
 */
export const listPasskeys = onCall(options, async (request) => {
  const uid = requireUid(request);
  const snapshot = await db()
    .collection(CREDENTIALS)
    .where("uid", "==", uid)
    .get();

  return {
    passkeys: snapshot.docs.map((doc) => {
      const data = doc.data() as StoredCredential & {
        createdAt?: FirebaseFirestore.Timestamp;
        lastUsedAt?: FirebaseFirestore.Timestamp | null;
      };
      return {
        credentialId: doc.id,
        deviceName: data.deviceName,
        createdAt: data.createdAt?.toMillis() ?? null,
        lastUsedAt: data.lastUsedAt?.toMillis() ?? null,
      };
    }),
  };
});

/** Removes one of the caller's passkeys. Never anybody else's. */
export const deletePasskey = onCall(options, async (request) => {
  const uid = requireUid(request);
  const { credentialId } = request.data ?? {};
  requireString(credentialId, "credentialId");

  const ref = db().collection(CREDENTIALS).doc(credentialId);
  const doc = await ref.get();
  if (!doc.exists) return { deleted: false };

  if ((doc.data() as StoredCredential).uid !== uid) {
    throw new HttpsError("permission-denied", "That passkey is not yours.");
  }

  await ref.delete();
  return { deleted: true };
});

// ---------------------------------------------------------------------------
// Challenges
// ---------------------------------------------------------------------------

/**
 * Records a challenge so the matching `finish` call can prove it issued it.
 *
 * A challenge the client chose would make the whole ceremony replayable, so
 * this is always the server-generated one, stored server-side, and spent on
 * first use.
 */
async function storeChallenge(
  challenge: string,
  type: "registration" | "authentication",
  uid?: string
): Promise<string> {
  const ref = db().collection(CHALLENGES).doc();
  await ref.set({
    challenge,
    type,
    uid: uid ?? null,
    // A Timestamp rather than a plain number, so a Firestore TTL policy can be
    // pointed at this field — TTL only recognises date-and-time values. The
    // policy is only housekeeping: a challenge that is used gets deleted on the
    // spot below, and expiry is enforced by comparing against this value, not
    // by the document's absence. What TTL clears up is the abandoned ones,
    // where somebody opened the sheet and walked away.
    //
    //   gcloud firestore fields ttls update expiresAt \
    //     --collection-group=passkeyChallenges --enable-ttl
    expiresAt: Timestamp.fromMillis(Date.now() + CHALLENGE_TTL_MS),
    createdAt: FieldValue.serverTimestamp(),
  });
  return ref.id;
}

/**
 * Reads a challenge back and deletes it in the same breath.
 *
 * The delete is the single-use guarantee, and it happens before verification
 * rather than after: a challenge that fails verification is spent too, or a
 * captured assertion could be retried against it until something worked.
 */
async function consumeChallenge(
  challengeId: string,
  type: "registration" | "authentication",
  uid?: string
): Promise<string> {
  const ref = db().collection(CHALLENGES).doc(challengeId);
  const doc = await ref.get();
  if (doc.exists) await ref.delete();

  if (!doc.exists) {
    throw new HttpsError("failed-precondition", "That request has expired. Please try again.");
  }

  const data = doc.data() as {
    challenge: string;
    type: string;
    uid: string | null;
    expiresAt: Timestamp;
  };

  if (data.type !== type || (uid !== undefined && data.uid !== uid)) {
    throw new HttpsError("failed-precondition", "That request does not match. Please try again.");
  }
  if (Date.now() > data.expiresAt.toMillis()) {
    throw new HttpsError("failed-precondition", "That request has expired. Please try again.");
  }

  return data.challenge;
}

// ---------------------------------------------------------------------------

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in before managing passkeys.");
  }
  return uid;
}

function requireString(value: unknown, name: string): asserts value is string {
  if (typeof value !== "string" || !value) {
    throw new HttpsError("invalid-argument", `Missing ${name}.`);
  }
}

/** Never returns a stack trace to a client. */
function describe(error: unknown): string {
  return error instanceof Error ? error.message : "Verification failed.";
}
