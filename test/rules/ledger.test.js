/**
 * The three collections the till writes as a side effect of a sale: the order
 * number counter, the day's rollup, and the change log.
 *
 * All three are awkward for the same reason — the writer is the till, so the
 * rules cannot say "server only". What they can do is refuse the writes that
 * are never part of ringing up a sale.
 */
import { beforeAll, afterAll, beforeEach, describe, test } from 'vitest';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, getDocs, collection, serverTimestamp, Timestamp } from 'firebase/firestore';
import {
  newTestEnv, as, seed, seedStore, seedOutsider, minutesAgo,
  assertFails, assertSucceeds, STORE, OWNER, MANAGER, STAFF, OUTSIDER,
} from './harness.js';

let env;
beforeAll(async () => { env = await newTestEnv('rules-ledger'); });
afterAll(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await seedStore(env);
  await seedOutsider(env);
});

const DATE = '2026-09-03';

describe('order number counters', () => {
  const counter = (db) => doc(db, 'stores', STORE, 'counters', DATE);

  test('a member starts the day', async () => {
    await assertSucceeds(setDoc(counter(as(env, STAFF)), { nextOrderNo: 1 }));
  });

  test('it only ever goes up', async () => {
    await seed(env, (db) => setDoc(counter(db), { nextOrderNo: 10 }));
    await assertSucceeds(updateDoc(counter(as(env, STAFF)), { nextOrderNo: 11 }));
  });

  test('winding it back is how one number gets issued twice', async () => {
    await seed(env, (db) => setDoc(counter(db), { nextOrderNo: 10 }));
    await assertFails(updateDoc(counter(as(env, STAFF)), { nextOrderNo: 5 }));
    await assertFails(updateDoc(counter(as(env, STAFF)), { nextOrderNo: 10 }));
    // Even a manager: there is no legitimate reason, and the damage is the same.
    await assertFails(updateDoc(counter(as(env, MANAGER)), { nextOrderNo: 5 }));
  });

  test('deleting it does the same thing more thoroughly', async () => {
    await seed(env, (db) => setDoc(counter(db), { nextOrderNo: 10 }));
    await assertFails(deleteDoc(counter(as(env, STAFF))));
    await assertFails(deleteDoc(counter(as(env, OWNER))));
  });

  test('it holds one field and nothing else', async () => {
    await assertFails(setDoc(counter(as(env, STAFF)), { nextOrderNo: 1, note: 'hello' }));
    await assertFails(setDoc(counter(as(env, STAFF)), { nextOrderNo: 'one' }));
  });

  test('another store\'s counter is out of reach', async () => {
    await assertFails(setDoc(counter(as(env, OUTSIDER)), { nextOrderNo: 1 }));
  });
});

describe('the daily rollup', () => {
  const stats = (db, date = DATE) => doc(db, 'stores', STORE, 'dailyStats', date);

  test('a member files a day under its own date', async () => {
    await assertSucceeds(setDoc(stats(as(env, STAFF)), {
      businessDate: DATE, revenue: 100, orderCount: 1 }));
  });

  test('a day cannot be filed under the wrong date', async () => {
    await assertFails(setDoc(stats(as(env, STAFF)), {
      businessDate: '2026-01-01', revenue: 100, orderCount: 1 }));
  });

  test('a day\'s takings are never removed', async () => {
    await seed(env, (db) => setDoc(stats(db), { businessDate: DATE, revenue: 100 }));
    await assertFails(deleteDoc(stats(as(env, STAFF))));
    await assertFails(deleteDoc(stats(as(env, MANAGER))));
    await assertFails(deleteDoc(stats(as(env, OWNER))));
  });

  test('another store\'s day is out of reach', async () => {
    await assertFails(setDoc(stats(as(env, OUTSIDER)), { businessDate: DATE, revenue: 1 }));
  });

  /**
   * The gap the rules file admits to at the end of itself: every figure here
   * arrives as a `FieldValue.increment` from the transaction that writes the
   * order, and a rule sees the result, not the delta. So a member writing to
   * Firestore directly can move a day's revenue without touching an order.
   *
   * Asserted rather than left implicit, so that the day this is fixed — by
   * moving the rollup to a Firestore trigger and closing the collection to
   * clients — this test fails and says exactly what changed.
   */
  test('KNOWN GAP: a member can rewrite a day\'s revenue without touching an order', async () => {
    await seed(env, (db) => setDoc(stats(db), { businessDate: DATE, revenue: 10_000, orderCount: 40 }));
    await assertSucceeds(setDoc(stats(as(env, STAFF)), {
      businessDate: DATE, revenue: 1, orderCount: 1 }));
  });
});

describe('the change log', () => {
  const log = (db, id = 'log1') => doc(db, 'stores', STORE, 'auditLogs', id);
  const entry = (over = {}) => ({
    action: 'menu.update', byUid: STAFF, byName: 'uid-staff',
    at: serverTimestamp(), targetId: 'i1', ...over,
  });

  test('a manager reads it — this is the whole point of it existing', async () => {
    await seed(env, (db) => setDoc(log(db), { ...entry(), at: minutesAgo(1) }));
    await assertSucceeds(getDocs(collection(as(env, MANAGER), 'stores', STORE, 'auditLogs')));
    await assertSucceeds(getDocs(collection(as(env, OWNER), 'stores', STORE, 'auditLogs')));
  });

  test('staff do not read it — being logged is not the same as seeing the log', async () => {
    await seed(env, (db) => setDoc(log(db), { ...entry(), at: minutesAgo(1) }));
    await assertFails(getDocs(collection(as(env, STAFF), 'stores', STORE, 'auditLogs')));
  });

  test('staff write their own entries, because they are the ones acting', async () => {
    await assertSucceeds(setDoc(log(as(env, STAFF)), entry()));
  });

  test('you cannot write somebody else\'s name onto your own void', async () => {
    await assertFails(setDoc(log(as(env, STAFF)), entry({ byUid: MANAGER })));
    await assertFails(setDoc(log(as(env, MANAGER)), entry({ byUid: OWNER })));
  });

  test('an entry cannot be back-dated into the middle of a list nobody scrolls', async () => {
    await assertFails(setDoc(log(as(env, STAFF)), entry({ at: minutesAgo(60 * 24) })));
    await assertFails(setDoc(log(as(env, STAFF)), entry({ at: Timestamp.now() })));
  });

  test('the log is append-only — no edits, no deletions, by anyone', async () => {
    await seed(env, (db) => setDoc(log(db), { ...entry(), at: minutesAgo(1) }));
    await assertFails(updateDoc(log(as(env, OWNER)), { action: 'something.else' }));
    await assertFails(deleteDoc(log(as(env, OWNER))));
    await assertFails(deleteDoc(log(as(env, MANAGER))));
  });

  test('another store\'s log is out of reach', async () => {
    await assertFails(getDocs(collection(as(env, OUTSIDER), 'stores', STORE, 'auditLogs')));
    await assertFails(setDoc(log(as(env, OUTSIDER)), entry({ byUid: OUTSIDER })));
  });

  // Entries can never be deleted, by design, so anything written here is
  // permanent — which makes an unbounded create rule a way to fill a shop's
  // own change history with junk it can never clear.
  describe('what an entry may contain', () => {
    test('a field nobody writes is refused', async () => {
      await assertFails(setDoc(log(as(env, STAFF)), entry({ payload: 'x' })));
    });

    test('the pieces the app actually sends are accepted', async () => {
      await assertSucceeds(setDoc(log(as(env, STAFF)), entry({
        before: { orderNo: 1, businessDate: DATE, total: 100 },
        after: { orderNo: 1, businessDate: DATE, total: 90 },
        note: 'Rang up twice',
      })));
    });

    test('a null optional is not the same as a wrong one', async () => {
      // `AuditLog.toMap()` writes nulls for the fields an entry does not use,
      // so refusing null here would refuse every menu-price change.
      await assertSucceeds(setDoc(log(as(env, STAFF)), entry({
        targetId: null, before: null, after: null, note: null, byName: null,
      })));
    });

    test('long strings are refused', async () => {
      await assertFails(setDoc(log(as(env, STAFF)), entry({ note: 'x'.repeat(501) })));
      await assertFails(setDoc(log(as(env, STAFF)), entry({ targetId: 'x'.repeat(201) })));
      await assertFails(setDoc(log(as(env, STAFF)), entry({ byName: 'x'.repeat(201) })));
      await assertFails(setDoc(log(as(env, STAFF)), entry({ action: 'x'.repeat(41) })));
    });

    test('a snapshot cannot be a payload', async () => {
      const wide = {};
      for (let i = 0; i < 21; i++) wide['k' + i] = i;
      await assertFails(setDoc(log(as(env, STAFF)), entry({ before: wide })));
      await assertFails(setDoc(log(as(env, STAFF)), entry({ after: wide })));
    });

    test('an action the rules have never heard of still writes', async () => {
      // Bounded, not enumerated, and on purpose: the entry is written inside
      // the same transaction as the change, so a rule that refused an
      // unrecognised action would turn "somebody added a fifth action to the
      // app" into "this shop can no longer void an order".
      await assertSucceeds(setDoc(log(as(env, STAFF)), entry({ action: 'issue_refund' })));
    });
  });
});
