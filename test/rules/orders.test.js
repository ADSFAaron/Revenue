/**
 * `orders/{orderId}` — the shop's books.
 *
 * Append-only, correctable by whoever rang it up for five minutes, by a
 * manager forever, and deletable by nobody. The five minutes are measured
 * against the *server's* clock, which is the part worth testing: it was once
 * measured against a clock the client sent.
 */
import { beforeAll, afterAll, beforeEach, describe, test } from 'vitest';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, getDocs, collection, serverTimestamp, Timestamp } from 'firebase/firestore';
import {
  newTestEnv, as, anon, seed, seedStore, seedOutsider, order, minutesAgo, minutesAhead,
  assertFails, assertSucceeds, STORE, OWNER, MANAGER, STAFF, OUTSIDER,
} from './harness.js';

let env;
beforeAll(async () => { env = await newTestEnv('rules-orders'); });
afterAll(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await seedStore(env);
  await seedOutsider(env);
});

const orders = (db) => collection(db, 'stores', STORE, 'orders');
const anOrder = (db, id = 'o1') => doc(db, 'stores', STORE, 'orders', id);

/** Puts an order in place with a chosen creation time, past the rules. */
const existing = (over = {}) =>
  seed(env, (db) => setDoc(anOrder(db), order({ createdAt: minutesAgo(0), ...over })));

describe('reading', () => {
  test('a member may read the store\'s orders', async () => {
    await existing();
    await assertSucceeds(getDocs(orders(as(env, STAFF))));
  });

  test('another store\'s owner may not', async () => {
    await existing();
    await assertFails(getDocs(orders(as(env, OUTSIDER))));
    await assertFails(getDoc(anOrder(as(env, OUTSIDER))));
  });

  test('signed out reads nothing', async () => {
    await existing();
    await assertFails(getDocs(orders(anon(env))));
  });
});

describe('ringing one up', () => {
  test('a member may, with the server\'s timestamp', async () => {
    await assertSucceeds(setDoc(anOrder(as(env, STAFF)), {
      ...order(), createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });

  test('a non-member may not', async () => {
    await assertFails(setDoc(anOrder(as(env, OUTSIDER)), {
      ...order(), createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });

  test('a client-chosen createdAt is refused', async () => {
    // The attack the rule exists for: `createdAt` a year ahead would leave
    // `request.time < createdAt + 5m` true for a year — an unbounded licence
    // to rewrite your own orders without a manager.
    await assertFails(setDoc(anOrder(as(env, STAFF)), {
      ...order(), createdAt: minutesAhead(60 * 24 * 365), updatedAt: serverTimestamp() }));
    await assertFails(setDoc(anOrder(as(env, STAFF)), {
      ...order(), createdAt: minutesAgo(60), updatedAt: serverTimestamp() }));
  });

  test('an order with no createdAt at all is refused', async () => {
    await assertFails(setDoc(anOrder(as(env, STAFF)), order()));
  });
});

describe('the five-minute correction window', () => {
  test('staff may correct a fresh order', async () => {
    await existing({ createdAt: minutesAgo(1) });
    await assertSucceeds(updateDoc(anOrder(as(env, STAFF)), { total: 120, subtotal: 120 }));
  });

  test('staff may not correct one after the window has passed', async () => {
    await existing({ createdAt: minutesAgo(10) });
    await assertFails(updateDoc(anOrder(as(env, STAFF)), { total: 120 }));
  });

  test('a manager may correct one at any age — this is the void-at-end-of-shift path', async () => {
    await existing({ createdAt: minutesAgo(600) });
    await assertSucceeds(updateDoc(anOrder(as(env, MANAGER)), { status: 'voided', voidedBy: MANAGER }));
    await existing({ createdAt: minutesAgo(600) });
    await assertSucceeds(updateDoc(anOrder(as(env, OWNER)), { status: 'voided', voidedBy: OWNER }));
  });

  test('the window does not open for another store', async () => {
    await existing({ createdAt: minutesAgo(1) });
    await assertFails(updateDoc(anOrder(as(env, OUTSIDER)), { total: 120 }));
  });
});

describe('what an edit may not change', () => {
  test('an edit may not move the clock and buy itself a new window', async () => {
    await existing({ createdAt: minutesAgo(1) });
    await assertFails(updateDoc(anOrder(as(env, STAFF)), { createdAt: minutesAhead(60) }));
    // Not even a manager, who has no need to.
    await assertFails(updateDoc(anOrder(as(env, MANAGER)), { createdAt: minutesAhead(60) }));
  });

  test('an edit may change what was sold, never who rang it up', async () => {
    await existing({ createdAt: minutesAgo(1) });
    await assertSucceeds(updateDoc(anOrder(as(env, STAFF)), { total: 150 }));
    await assertFails(updateDoc(anOrder(as(env, STAFF)), { createdBy: MANAGER }));
    await assertFails(updateDoc(anOrder(as(env, MANAGER)), { createdBy: OWNER }));
  });
});

describe('deletion', () => {
  test('an order is never deletable — a voided one stays auditable', async () => {
    await existing();
    await assertFails(deleteDoc(anOrder(as(env, STAFF))));
    await assertFails(deleteDoc(anOrder(as(env, MANAGER))));
    await assertFails(deleteDoc(anOrder(as(env, OWNER))));
  });
});
