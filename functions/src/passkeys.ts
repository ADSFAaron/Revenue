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
import { logger } from "firebase-functions/v2";
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from "@simplewebauthn/server";
import type {
  AuthenticationResponseJSON,
  RegistrationResponseJSON,
} from "@simplewebauthn/server";

import {
  CALLABLE_OPTIONS,
  CHALLENGES,
  CHALLENGE_TTL_MS,
  CREDENTIALS,
  EXPECTED_ORIGINS,
  RP_ID,
  RP_NAME,
} from "./config.js";

/**
 * App Check enforced, including on the two authentication calls that take no
 * signed-in user. Those are the ones that most need it: `beginPasskey-
 * Authentication` mints a challenge for anybody who asks, and before
 * enforcement that was an unauthenticated write to `passkeyChallenges` that
 * any script could run in a loop.
 */
const options = CALLABLE_OPTIONS;

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
  /**
   * A hint the browser uses to say "tap your phone" rather than "insert your
   * key".
   *
   * Plain `string[]`, which is what @simplewebauthn 14 changed every
   * transport-carrying interface to. It used to be a union
   * (`AuthenticatorTransportFuture`) and the temptation on upgrading is to
   * follow the rename to `AuthenticatorTransport` — that is the wrong move.
   * The value originates at the client, so it was never constrained to a
   * union the server chose, and the two consumers below only pass it back out
   * for a browser to read. WebAuthn requires a client to ignore a transport it
   * does not recognise, which is why widening it costs nothing here.
   */
  transports: string[];
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
      // 'required', because the verifying side already requires it:
      // @simplewebauthn's `requireUserVerification` defaults to `true` on both
      // `verifyRegistrationResponse` and `verifyAuthenticationResponse`, and
      // neither call below overrides it. Asking for 'preferred' while
      // enforcing 'required' is the worst of the two — an authenticator that
      // skipped the fingerprint would sail through the whole ceremony and then
      // be refused here, with a message about the passkey not being recognised
      // that describes nothing that actually happened. Ask for what is
      // enforced.
      userVerification: "required",
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
    transports: toTransports(credential.transports),
    deviceName: typeof deviceName === "string" && deviceName.trim()
      ? deviceName.trim().slice(0, 60)
      : "Unnamed device",
  };

  // WebAuthn §7.1 ends with "if the credentialId is already known then the
  // Relying Party SHOULD fail the registration ceremony", and `.set()` did the
  // opposite: it overwrote whatever was already there.
  //
  // The credential id is this document's id and the authenticator chooses it.
  // With `attestationType: "none"` nothing here attests that the authenticator
  // is a real one, so a caller running their own picks any id it likes. That
  // is not a way *in* — the record it writes carries its own public key, so it
  // can only ever sign in as itself. It is a way to delete somebody else's
  // passkey by registering on top of it, and the ids are not secret from the
  // people best placed to try: `DeviceAccount.passkeyIds` keeps every
  // colleague's credential id in one unencrypted store on the shared tablet.
  //
  // A transaction rather than `.create()`, because re-registering an id you
  // already own is not the attack and should not be an error.
  const ref = db().collection(CREDENTIALS).doc(credential.id);
  await db().runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists && (existing.data() as StoredCredential).uid !== uid) {
      throw new HttpsError(
        "already-exists",
        "That passkey is already registered.",
      );
    }
    tx.set(ref, {
      ...record,
      createdAt: FieldValue.serverTimestamp(),
      lastUsedAt: null,
    });
  });

  return { credentialId: credential.id, deviceName: record.deviceName };
});

// ---------------------------------------------------------------------------
// Signing in with a passkey
// ---------------------------------------------------------------------------

/**
 * How many credential ids a caller may narrow the ceremony to. A till with
 * more than a handful of people on it is not the case this is for, and an
 * unbounded list is a free way to make us build a large response.
 */
const MAX_ALLOWED_CREDENTIALS = 10;

/**
 * Issues an authentication challenge. Deliberately unauthenticated — the whole
 * point is to sign somebody in who is not signed in yet.
 *
 * Credentials are discoverable, so with no `allowCredentials` the authenticator
 * shows the person every passkey it holds for us and tells us which one they
 * picked. That is right when the app does not know who is asking, and wrong on
 * the operator picker, where they have just tapped their own name: the OS would
 * ask them to choose all over again, from a list of their colleagues.
 *
 * So the caller may narrow it. `credentialIds` is a hint to the authenticator
 * and nothing more — the assertion is still verified against the stored public
 * key in `finishPasskeyAuthentication`, which looks the credential up by the
 * id the authenticator signed, not by anything sent here.
 *
 * Since `allowedCredentials` started dropping ids it has no record of, the
 * reply does reflect what is stored — ask with an id and the answer tells you
 * whether it exists. That is not an enumeration oracle: a credential id is a
 * random value from an authenticator, not something anybody guesses, and the
 * only people holding one already had it. This endpoint still cannot be asked
 * "does this email have a passkey?", because it is still never told an email.
 */
export const beginPasskeyAuthentication = onCall(options, async (request) => {
  const requested = request.data?.credentialIds;
  const ids = Array.isArray(requested)
    ? requested
        .filter((id: unknown): id is string => typeof id === "string" && id.length > 0)
        .slice(0, MAX_ALLOWED_CREDENTIALS)
    : [];
  const allowCredentials = ids.length ? await allowedCredentials(ids) : [];

  const created = await generateAuthenticationOptions({
    rpID: RP_ID,
    // Enforced on the way back in, so asked for on the way out — see the note
    // in `beginPasskeyRegistration`.
    userVerification: "required",
    ...(allowCredentials.length ? { allowCredentials } : {}),
  });

  const challengeId = await storeChallenge(created.challenge, "authentication");
  return { challengeId, options: created };
});

/**
 * The allow-list entries for `credentialIds`, each carrying the transports its
 * credential was registered with.
 *
 * `transports` is not decoration here, and omitting it was a crash rather than
 * a missing hint. The Dart client parses every entry with generated code that
 * casts `json['transports']` to a *non-nullable* `List<dynamic>`
 * (passkeys_platform_interface, credential.g.dart), so an entry without the
 * field threw "type 'Null' is not a subtype of type 'List<dynamic>'" before
 * the authenticator was ever asked anything.
 *
 * It threw on the operator picker only, because that is the one caller that
 * sends ids at all. The sign-in screen's own passkey button sends none, gets
 * no `allowCredentials` back, and never reached the offending parse — which is
 * why this survived every test that went in through the front door.
 *
 * Sending the real transports rather than an empty array is the other half of
 * it: that list is what lets the authenticator say "use your phone" instead of
 * offering to wait for a security key nobody owns.
 *
 * Ids with no stored credential are dropped. `finishPasskeyAuthentication`
 * looks a credential up by the id the authenticator signed, so an assertion
 * from one of these would be refused anyway; passing it on only widens what
 * the person is asked to choose from. If every id is stale the list comes back
 * empty and the ceremony falls back to discoverable credentials — the same
 * thing the sign-in screen does.
 */
async function allowedCredentials(
  ids: string[],
): Promise<{ id: string; transports: string[] }[]> {
  const docs = await db().getAll(
    ...ids.map((id) => db().collection(CREDENTIALS).doc(id)),
  );
  return docs
    .filter((doc) => doc.exists)
    .map((doc) => ({
      id: doc.id,
      transports: (doc.data() as StoredCredential).transports ?? [],
    }));
}

/**
 * Verifies the assertion and mints a Firebase custom token for the account the
 * credential belongs to.
 *
 * This is the only function that can hand out a session, so it is the one
 * worth reading twice. Seven things are checked, and all seven matter: the
 * challenge is one we issued, is unspent and has not expired; the origin is
 * one of ours; the RP ID matches; the signature verifies against the stored
 * public key; the person was verified by their authenticator, not merely
 * present (`requireUserVerification` defaults to `true` and nothing here turns
 * it off); and the signature counter has not gone backwards.
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
    // Deliberately not `describe(error)`. The library's messages are precise in
    // a way that only helps somebody probing: "Response counter value 4 was
    // lower than expected 9" hands back a counter, and an origin mismatch hands
    // back the configuration. The two branches around this one go to the
    // trouble of giving an unknown credential and a bad signature the same
    // wording; this one used to undo that. The detail belongs in the log, where
    // it is still there to debug with.
    logger.warn("passkey assertion rejected", {
      credentialId: doc.id,
      reason: describe(error),
    });
    throw new HttpsError("unauthenticated", "That passkey is not recognised.");
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

/**
 * Removes every passkey belonging to these accounts. Called by `deleteAccount`,
 * not by any client.
 *
 * A credential that outlives its account is not a leftover row, it is a live
 * way in: `finishPasskeyAuthentication` verifies the assertion, finds the
 * credential, and mints a custom token for a uid that no longer exists — and
 * `signInWithCustomToken` *creates* an account for a uid it does not find, so
 * the deleted login comes back. It comes back with no `users/{uid}` document,
 * so every security rule refuses it, but "signed in as a ghost" is not the
 * outcome account deletion is supposed to have. The header of account.ts says
 * the account goes and the personal data with it; this is part of that
 * promise, and `deviceName` is personal data besides.
 *
 * Returns how many went, for the log.
 */
export async function deletePasskeysFor(uids: string[]): Promise<number> {
  let deleted = 0;
  // `in` takes at most 30 values, and an owner deleting a store can be taking
  // more colleagues than that with them.
  for (let i = 0; i < uids.length; i += 30) {
    const snapshot = await db()
      .collection(CREDENTIALS)
      .where("uid", "in", uids.slice(i, i + 30))
      .get();
    // Same 400 as account.ts, and the same reason: a batch is capped at 500.
    for (let j = 0; j < snapshot.docs.length; j += 400) {
      const batch = db().batch();
      for (const doc of snapshot.docs.slice(j, j + 400)) batch.delete(doc.ref);
      await batch.commit();
    }
    deleted += snapshot.size;
  }
  return deleted;
}

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

  // In a transaction, because a read followed by a delete is not single use.
  // Two calls arriving together both read the document before either deletes
  // it, and both then hold a challenge the other has supposedly spent — and
  // spending it is the one thing standing between a captured assertion and a
  // replay of it. The transaction makes the loser of that race fail its read.
  //
  // The delete still happens before any of the checks below, for the reason it
  // always did: a challenge that fails verification is spent too, or an
  // assertion could be retried against it until something worked.
  const data = await db().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) return null;
    tx.delete(ref);
    return doc.data() as {
      challenge: string;
      type: string;
      uid: string | null;
      expiresAt: Timestamp;
    };
  });

  if (!data) {
    throw new HttpsError("failed-precondition", "That request has expired. Please try again.");
  }

  if (data.type !== type || (uid !== undefined && data.uid !== uid)) {
    throw new HttpsError("failed-precondition", "That request does not match. Please try again.");
  }
  if (Date.now() > data.expiresAt.toMillis()) {
    throw new HttpsError("failed-precondition", "That request has expired. Please try again.");
  }

  return data.challenge;
}

// ---------------------------------------------------------------------------

/**
 * The transports to store, out of whatever the client sent.
 *
 * `credential.transports` is `response.response.transports` — client-supplied,
 * and @simplewebauthn passes it straight through without looking at it. This
 * array is stored and then handed back out to authenticators, and WebAuthn
 * defines a handful of transports rather than an unbounded list, so a caller
 * that sends ten thousand of them gets a cap instead of a document.
 */
function toTransports(value: string[] | undefined): string[] {
  return (value ?? [])
    .filter((t) => typeof t === "string" && t.length > 0 && t.length <= 32)
    .slice(0, 8);
}

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
