/**
 * Checking an invite code before there is an account to check it with.
 *
 * This exists because of one line that used to be in firestore.rules:
 *
 *   allow get: if true;
 *
 * Registration asks about a code on its first screen, deliberately — a
 * mistyped code should be caught there rather than after a whole form has been
 * filled in — and at that moment the person has no account, so no rule
 * requiring sign-in could serve them. The collection was opened to
 * unauthenticated reads instead, on the reasoning that guessing one of 31^6
 * codes inside a 30-minute window is not a practical attack.
 *
 * That reasoning was about *guessing* a code. It said nothing about holding
 * one. A code that has been read out to the wrong person, glimpsed on a
 * counter, or kept by somebody who has since left gave its holder an
 * unauthenticated read of `storeId`, `storeName`, `role` and `createdBy` —
 * and `storeId` is the id every other rule in that file is keyed on.
 *
 * Asking a server instead fixes both halves. The rule becomes
 * `allow get: if signedIn()`, and this function answers the pre-account
 * question with the two things the screen actually shows and nothing else:
 * which store, and which role. `storeId` never leaves the server.
 *
 * `enforceAppCheck` comes with CALLABLE_OPTIONS, which is the mitigation the
 * old rule's comment named and nothing implemented. A code can now only be
 * tested from a genuine build of this app, which is a far better bound on
 * guessing than counting the alphabet was.
 */

import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { CALLABLE_OPTIONS } from "./config.js";

/**
 * The alphabet a code is drawn from, and its length.
 *
 * Kept in step with `Invite` in lib/models/invite.dart — upper-case
 * alphanumerics minus the characters that get confused when read aloud across
 * a kitchen (`0 O 1 I L`). Normalising here rather than trusting the client to
 * have done it: this is a public endpoint now, and the document id it looks up
 * has to be one this project could actually have issued.
 */
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 6;

function normalise(input: unknown): string {
  if (typeof input !== "string") return "";
  let out = "";
  for (const char of input.toUpperCase()) {
    if (ALPHABET.includes(char)) out += char;
  }
  return out;
}

/**
 * Whether a code can still be spent, and what it grants.
 *
 * Deliberately not `notFound` versus `alreadyUsed` collapsed into one answer.
 * They send a person to two different places — "check the code with whoever
 * gave it to you" and "ask for a new one" — and the app has always
 * distinguished them (`InviteFailure` in
 * lib/database/invite_repository.dart). Telling an unauthenticated caller that
 * a code they already hold has been used reveals nothing they could not
 * discover by trying to redeem it.
 *
 * Nothing is written. This only reads.
 */
export const checkInvite = onCall(CALLABLE_OPTIONS, async (request) => {
  const code = normalise(request.data?.code);
  if (code.length !== CODE_LENGTH) {
    throw new HttpsError("invalid-argument", "An invite code is 6 characters.");
  }

  const snap = await getFirestore().collection("invites").doc(code).get();
  if (!snap.exists) {
    throw new HttpsError(
      "not-found",
      "No invite with that code. Check it with whoever gave it to you.",
    );
  }

  const data = snap.data() ?? {};

  if (data.usedBy != null) {
    throw new HttpsError(
      "already-exists",
      "That code has already been used. Codes work once — ask for a new one.",
    );
  }

  const expiresAt = data.expiresAt as Timestamp | undefined;
  if (!expiresAt || expiresAt.toMillis() <= Date.now()) {
    throw new HttpsError(
      "deadline-exceeded",
      "That code has expired. Ask for a new one.",
    );
  }

  // The store's name and the role, and that is the whole answer. `storeId`,
  // `createdBy` and the rest stay here — the app does not need them to draw
  // "You are joining <store> as <role>", and `redeem()` reads the document
  // itself once the account exists.
  return {
    code,
    storeName: (data.storeName as string | undefined) ?? "",
    role: (data.role as string | undefined) ?? "staff",
    expiresAt: expiresAt.toMillis(),
  };
});
