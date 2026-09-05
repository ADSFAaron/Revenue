/**
 * A ceiling on the one call in this project that costs real money.
 *
 * Reading a menu off photographs is a paid call to a third-party model, and it
 * is the only thing here whose unit cost is measured in cents rather than in
 * millionths of one. Everything else — a Firestore write, a function
 * invocation — needs millions of repetitions to add up to a coffee.
 *
 * `requireMenuEditor` already checks that the caller owns or manages the store
 * whose menu they are importing. That is the right check and it is not a
 * perimeter: registration makes you the owner of a brand-new store, and this
 * project has no email verification, so anybody with a keyboard is an owner
 * about four seconds after deciding to be one. The role check protects a shop
 * from its own staff. It does not protect the project from a stranger.
 *
 * Hence two counters, both checked in one transaction before any model is
 * called:
 *
 *   * **Per store.** A real shop imports its menu when it opens and re-does it
 *     when the menu changes — a handful of times ever, not a handful of times
 *     an hour. [PER_STORE_DAILY] is set well above honest use and far below
 *     anything worth scripting.
 *
 *   * **Per project.** The one that actually bounds the bill. Per-store limits
 *     multiply by the number of stores, and stores are free to create, so a
 *     per-store cap alone caps nothing. This one is a hard ceiling on how much
 *     the model can be asked to do in a day no matter who is asking.
 *
 * Neither counter is refunded when recognition fails. A failed import has
 * usually been through several model attempts by the time it gives up, and
 * those were charged for; refunding would make failure the cheap way to spend
 * the budget.
 *
 * Both documents live outside anything a client may touch — `firestore.rules`
 * ends in a deny-all, and no rule matches these paths — so the only writer is
 * this function, running as admin.
 */

import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

/**
 * Imports one store may run in a day.
 *
 * Four photos each, so this is sixteen pages of menu daily. A shop that
 * genuinely needs more is a conversation, not a config value.
 */
export const PER_STORE_DAILY = 5;

/**
 * Imports the whole project may run in a day, across every store.
 *
 * This is the number that decides the worst case on a month's bill. Raise it
 * when there are enough real shops to bump into it — the logs below say when
 * that happens, and say it before anybody complains.
 */
export const PROJECT_DAILY = 200;

/**
 * Slips one store may read in a day.
 *
 * **A different kind of number from the menu one, and worth understanding
 * before raising it.** A menu import happens when a shop opens and when its
 * menu changes — a handful of times ever. Reading an order slip happens *per
 * order*, so this is the first paid call in the project whose usage scales
 * with how busy a shop is. Sixty is a normal lunch and dinner service on the
 * slips, not a whole day of every order: the till is the fast path, and this
 * is for the ones that arrive on paper.
 *
 * Raising it raises the bill in direct proportion. That is a decision about
 * money rather than about code, which is why the number is here with this
 * paragraph next to it rather than buried in a config.
 */
export const ORDER_SLIP_PER_STORE_DAILY = 60;

/** Slips the whole project may read in a day. See [PROJECT_DAILY]. */
export const ORDER_SLIP_PROJECT_DAILY = 600;

/** `stores/{storeId}/usage/menuImport` and `usage/menuImport`. */
const USAGE_DOC = "menuImport";

/** `stores/{storeId}/usage/orderSlip` and `usage/orderSlip`. */
const SLIP_USAGE_DOC = "orderSlip";

/**
 * The day a count belongs to, as `YYYY-MM-DD` in UTC.
 *
 * UTC rather than the shop's own trading day on purpose. A trading day is a
 * per-store setting and this counter is partly global, so the two cannot share
 * one definition; and a quota does not need to line up with the books. The
 * only visible effect is that the allowance resets at 08:00 in Taiwan.
 */
function today(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * How many are already spent, treating a count from an earlier day as zero.
 *
 * Rolling over by comparing the stored day, rather than by clearing the
 * documents on a schedule, means there is no scheduled function to deploy, pay
 * for, or discover has been failing quietly for a month.
 */
function spent(data: FirebaseFirestore.DocumentData | undefined, day: string): number {
  if (!data || data.day !== day) return 0;
  return typeof data.count === "number" ? data.count : 0;
}

/**
 * Claims one import, or refuses.
 *
 * Call before the model is reached, never after.
 *
 * @throws HttpsError `resource-exhausted` when either ceiling is reached.
 */
export async function reserveMenuImport(storeId: string): Promise<void> {
  await reserve(storeId, {
    label: "Menu import",
    doc: USAGE_DOC,
    perStore: PER_STORE_DAILY,
    perProject: PROJECT_DAILY,
    storeLimitMessage:
      `That is ${PER_STORE_DAILY} menu imports today, which is this store's ` +
      "limit. It resets tomorrow. If a menu keeps coming back wrong, a " +
      "flatter, brighter photograph usually reads better than another try " +
      "at the same one — or add the dishes by hand from Edit menu.",
    projectLimitMessage:
      "Menu reading is unavailable for the rest of today. This is a limit " +
      "on our side, not anything you did. Please try tomorrow, or add the " +
      "dishes by hand from Edit menu.",
  });
}

/**
 * Claims one slip reading, or refuses.
 *
 * Same shape, different ceilings, and a different sentence when it refuses:
 * somebody at a counter with a customer in front of them needs to be told to
 * type it in, not to come back tomorrow.
 */
export async function reserveOrderSlip(storeId: string): Promise<void> {
  await reserve(storeId, {
    label: "Order slip",
    doc: SLIP_USAGE_DOC,
    perStore: ORDER_SLIP_PER_STORE_DAILY,
    perProject: ORDER_SLIP_PROJECT_DAILY,
    storeLimitMessage:
      `That is ${ORDER_SLIP_PER_STORE_DAILY} slips read today, which is this ` +
      "store's limit. It resets tomorrow. Ring this one up on the order " +
      "screen in the meantime.",
    projectLimitMessage:
      "Slip reading is unavailable for the rest of today. This is a limit on " +
      "our side, not anything you did. Ring the order up on the order screen.",
  });
}

interface Ceiling {
  /** For the log line only. */
  label: string;
  doc: string;
  perStore: number;
  perProject: number;
  storeLimitMessage: string;
  projectLimitMessage: string;
}

async function reserve(storeId: string, ceiling: Ceiling): Promise<void> {
  const db = getFirestore();
  const day = today();
  const storeRef = db.doc(`stores/${storeId}/usage/${ceiling.doc}`);
  const projectRef = db.doc(`usage/${ceiling.doc}`);

  await db.runTransaction(async (tx) => {
    const [storeDoc, projectDoc] = await tx.getAll(storeRef, projectRef);
    const storeCount = spent(storeDoc.data(), day);
    const projectCount = spent(projectDoc.data(), day);

    if (storeCount >= ceiling.perStore) {
      // Named as a limit rather than as a failure, and it always says what to
      // do instead. This is somebody in the middle of a job, and "quota
      // exceeded" tells them nothing about how to finish it.
      throw new HttpsError("resource-exhausted", ceiling.storeLimitMessage);
    }

    if (projectCount >= ceiling.perProject) {
      // Nothing the caller did, and nothing they can fix, so it does not
      // pretend otherwise.
      logger.error(`${ceiling.label}: project daily ceiling reached`, {
        day,
        ceiling: ceiling.perProject,
        storeId,
      });
      throw new HttpsError("resource-exhausted", ceiling.projectLimitMessage);
    }

    const stamp = Timestamp.now();
    tx.set(storeRef, { day, count: storeCount + 1, updatedAt: stamp });
    tx.set(projectRef, { day, count: projectCount + 1, updatedAt: stamp });

    // Warns while there is still a day's headroom to react in, rather than at
    // the moment the ceiling stops somebody's import.
    if (projectCount + 1 >= ceiling.perProject * 0.8) {
      logger.warn(`${ceiling.label}: past 80% of the project daily ceiling`, {
        day,
        used: projectCount + 1,
        ceiling: ceiling.perProject,
      });
    }
  });
}
