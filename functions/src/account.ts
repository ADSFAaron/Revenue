/**
 * Deleting an account, and — when the person leaving is the owner — the store
 * with it.
 *
 * This has to be server-side, and not because of convenience. The security
 * rules say `allow delete: if false` on `users/{uid}`, `stores/{storeId}` and
 * `orders/{orderId}`: no client can remove any of them, which is deliberate,
 * because those are the documents every other rule trusts. The Admin SDK is
 * outside the rules, and it also deletes the Firebase Auth user without the
 * `requires-recent-login` re-authentication that `user.delete()` demands of a
 * client.
 *
 * Why the owner's departure takes the store: ownership lives only on
 * `users/{uid}.role`. There is no owner field on the store document, and the
 * rule that grants ownership (`claimsUnusedStore`) requires the store *not* to
 * exist. So an owner's user document disappearing leaves a store that can
 * never have an owner again — nobody can edit the menu, change settings or
 * invite anyone, forever. Deleting the store is the honest outcome, and it is
 * also what App Store guideline 5.1.1(v) asks for: the account goes, and the
 * personal data with it.
 */

import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { CALLABLE_OPTIONS } from "./config.js";

const options = CALLABLE_OPTIONS;

const db = () => getFirestore();

/**
 * How recently the caller must have proved who they are.
 *
 * `user.delete()` on a client demands `requires-recent-login` and this function
 * deliberately bypasses it — the Admin SDK is outside that check, which is what
 * lets the deletion finish without asking somebody to sign in again in the
 * middle of it. Bypassing the re-authentication was not meant to bypass the
 * *reason* for it: a session token lives a long time on a device that sits on a
 * counter all day, and this one call takes the store, every order in it, and
 * every colleague's login with it.
 *
 * Five minutes is the same window Firebase itself uses for recent login, and it
 * is comfortably longer than reading a confirmation dialog and typing a store
 * name into it.
 */
const RECENT_LOGIN_SECONDS = 5 * 60;

export const deleteAccount = onCall(options, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }

  // `auth_time` is when this session last actually authenticated, not when the
  // token was minted — a refresh does not move it, which is exactly the
  // property needed here.
  const authTime = request.auth?.token?.auth_time;
  if (typeof authTime !== "number" ||
      Date.now() / 1000 - authTime > RECENT_LOGIN_SECONDS) {
    throw new HttpsError(
      "failed-precondition",
      "Please sign in again before deleting your account.",
    );
  }

  const userRef = db().collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    // No profile to clean up; still remove the login, which is what the
    // person asked for.
    await getAuth().deleteUser(uid);
    return { deletedStore: false, removedMembers: 0 };
  }

  const data = userSnap.data() ?? {};
  const storeId = data.storeId as string | undefined;
  const isOwner = data.role === "owner";

  // Staff and managers: their membership and their login, nothing else. The
  // orders they rang up stay — they are the store's books, not the person's,
  // and `createdBy` is a uid that now refers to nobody.
  if (!isOwner || !storeId) {
    await userRef.delete();
    await getAuth().deleteUser(uid);
    return { deletedStore: false, removedMembers: 0 };
  }

  // The store's own name has to match what the client was shown, so a
  // mis-tapped confirmation cannot take a shop with it.
  //
  // Skipped when the store document is already gone, and that exception is the
  // whole reason a retry can finish. `recursiveDelete` below removes the store
  // document itself, so a run that failed *after* it leaves nothing to compare
  // against — the check would read an empty name, refuse every possible
  // confirmation, and the person would be permanently unable to complete a
  // deletion that is already most of the way done. There is also nothing left
  // for the guard to protect: it is here to stop a mis-tap taking a live shop,
  // and this shop is not live.
  const confirmation = (request.data?.storeName ?? "") as string;
  const storeRef = db().collection("stores").doc(storeId);
  const storeSnap = await storeRef.get();
  if (storeSnap.exists) {
    const storeName = (storeSnap.data()?.name ?? "") as string;
    if (confirmation.trim() !== storeName.trim()) {
      throw new HttpsError(
        "failed-precondition",
        "The store name did not match.",
      );
    }
  }

  // Everyone who belongs to this store loses their membership and their
  // login: without the store there is nothing for them to sign in to, and
  // leaving the accounts behind would leave people able to sign in to an app
  // that then tells them they belong nowhere.
  const members = await db()
    .collection("users")
    .where("storeId", "==", storeId)
    .get();

  const memberUids = members.docs.map((doc) => doc.id).filter((id) => id !== uid);

  // Invite codes live at the top level, so recursiveDelete on the store does
  // not reach them.
  const invites = await db()
    .collection("invites")
    .where("storeId", "==", storeId)
    .get();

  // Everyone *except* the caller. Their own document is deleted last, next to
  // their login, and the difference is not tidiness — it is the only thing
  // that makes a failed deletion recoverable.
  //
  // With it in this batch, a `recursiveDelete` that gave up half way (a big
  // shop, a deadline, a dropped connection) left the caller signed in with no
  // user document. The retry then reads `userSnap.exists === false`, takes the
  // early branch at the top of this function, deletes the login and reports
  // `deletedStore: false` — and the store, with every order in it, is orphaned
  // for good: ownership lives only on `users/{uid}.role`, and `claimsUnusedStore`
  // will not hand out a new owner for a store that already exists. Nobody can
  // ever edit, invite or delete it again.
  //
  // Kept back, a failure anywhere below leaves the caller exactly as they
  // were — able to sign in and run this again from the top, which is what the
  // ordering at the end of this function was always meant to guarantee.
  const stale = [
    ...invites.docs,
    ...members.docs.filter((doc) => doc.id !== uid),
  ];

  // A batch is capped at 500 writes and both of these collections are
  // unbounded — invite codes in particular accumulate for the life of a shop.
  // Over the cap the whole commit is rejected, so the deletion would fail on
  // exactly the long-lived stores that most need it to work.
  const BATCH_LIMIT = 400;
  for (let i = 0; i < stale.length; i += BATCH_LIMIT) {
    const batch = db().batch();
    for (const doc of stale.slice(i, i + BATCH_LIMIT)) batch.delete(doc.ref);
    await batch.commit();
  }

  // Everything under stores/{id} — menuItems, orders, dailyStats, counters,
  // auditLog — in one recursive pass. A busy shop has thousands of order
  // documents, which is the other reason this cannot be done from a client.
  await db().recursiveDelete(storeRef);

  if (memberUids.length > 0) {
    const result = await getAuth().deleteUsers(memberUids);
    if (result.failureCount > 0) {
      // Not fatal: the store and its data are already gone, and a login with
      // no user document cannot reach anything.
      logger.warn("some colleague logins survived", {
        storeId,
        failures: result.failureCount,
      });
    }
  }

  // Last, so that a failure anywhere above leaves the caller still able to
  // sign in and try again rather than locked out of a half-deleted store.
  // The document goes first and the login second: a login with no document is
  // a retry waiting to happen, a document with no login is unreachable.
  await userRef.delete();
  await getAuth().deleteUser(uid);

  return { deletedStore: true, removedMembers: memberUids.length };
});
