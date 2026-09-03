/**
 * `invites/{code}` — the only way into an existing store.
 *
 * Top level rather than under `stores/`, because it is validated by somebody
 * who belongs to no store yet. That is what makes it the most exposed
 * collection in the file, and why what a code reveals matters as much as what
 * it grants.
 */
import { beforeAll, afterAll, beforeEach, describe, test } from 'vitest';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, getDocs, collection, query, where, Timestamp } from 'firebase/firestore';
import {
  newTestEnv, as, anon, seed, seedStore, seedOutsider,
  assertFails, assertSucceeds, STORE, OTHER_STORE, OWNER, MANAGER, STAFF, OUTSIDER,
} from './harness.js';

let env;
beforeAll(async () => { env = await newTestEnv('rules-invites'); });
afterAll(async () => { await env.cleanup(); });

const CODE = 'ABC123';
const future = () => Timestamp.fromDate(new Date(Date.now() + 30 * 60_000));
const invite = (over = {}) => ({
  storeId: STORE, storeName: 'Test Shop', role: 'staff',
  createdBy: MANAGER, usedBy: null, expiresAt: future(),
  createdAt: Timestamp.now(), ...over,
});

beforeEach(async () => {
  await env.clearFirestore();
  await seedStore(env);
  await seedOutsider(env);
  await seed(env, (db) => setDoc(doc(db, 'invites', CODE), invite()));
});

describe('reading a code', () => {
  test('a signed-in caller may read one it knows', async () => {
    await assertSucceeds(getDoc(doc(as(env, 'uid-new'), 'invites', CODE)));
  });

  test('a signed-out caller may not', async () => {
    // This was `allow get: if true`, the one rule that let an anonymous caller
    // read anything — and a code carries the storeId every other rule is keyed
    // on. Registration asks the `checkInvite` callable instead.
    await assertFails(getDoc(doc(anon(env), 'invites', CODE)));
  });

  test('listing is how you would enumerate another store\'s codes', async () => {
    const managerDb = as(env, MANAGER);
    await assertSucceeds(getDocs(query(collection(managerDb, 'invites'), where('storeId', '==', STORE))));
    await assertFails(getDocs(query(collection(as(env, STAFF), 'invites'), where('storeId', '==', STORE))));
    await assertFails(getDocs(query(collection(as(env, OUTSIDER), 'invites'), where('storeId', '==', STORE))));
    await assertFails(getDocs(collection(managerDb, 'invites')));
  });
});

describe('issuing a code', () => {
  const fresh = (db, id = 'NEW123') => doc(db, 'invites', id);

  test('a manager issues one for their own store', async () => {
    await assertSucceeds(setDoc(fresh(as(env, MANAGER)), invite({ createdBy: MANAGER })));
    await assertSucceeds(setDoc(fresh(as(env, OWNER), 'NEW456'), invite({ createdBy: OWNER })));
  });

  test('staff do not issue codes', async () => {
    await assertFails(setDoc(fresh(as(env, STAFF)), invite({ createdBy: STAFF })));
  });

  test('nobody issues a code for a store they do not manage', async () => {
    await assertFails(setDoc(fresh(as(env, OUTSIDER)), invite({ createdBy: OUTSIDER })));
  });

  test('a code cannot be signed with somebody else\'s name', async () => {
    await assertFails(setDoc(fresh(as(env, MANAGER)), invite({ createdBy: OWNER })));
  });

  test('no code grants ownership', async () => {
    await assertFails(setDoc(fresh(as(env, OWNER)), invite({ createdBy: OWNER, role: 'owner' })));
  });

  test('a code cannot be born already spent', async () => {
    await assertFails(setDoc(fresh(as(env, MANAGER)), invite({ createdBy: MANAGER, usedBy: 'x' })));
  });

  test('a code has to expire', async () => {
    await assertFails(setDoc(fresh(as(env, MANAGER)), invite({ createdBy: MANAGER, expiresAt: null })));
    await assertFails(setDoc(fresh(as(env, MANAGER)), invite({ createdBy: MANAGER, expiresAt: 'soon' })));
  });
});

describe('spending a code', () => {
  test('once, on yourself', async () => {
    await assertSucceeds(updateDoc(doc(as(env, 'uid-new'), 'invites', CODE), { usedBy: 'uid-new' }));
  });

  test('not twice', async () => {
    await seed(env, (db) => setDoc(doc(db, 'invites', CODE), invite({ usedBy: 'first-person' })));
    await assertFails(updateDoc(doc(as(env, 'uid-new'), 'invites', CODE), { usedBy: 'uid-new' }));
  });

  test('not on somebody else', async () => {
    await assertFails(updateDoc(doc(as(env, 'uid-new'), 'invites', CODE), { usedBy: 'another-uid' }));
  });

  test('not after it expires', async () => {
    await seed(env, (db) => setDoc(doc(db, 'invites', CODE),
      invite({ expiresAt: Timestamp.fromDate(new Date(Date.now() - 60_000)) })));
    await assertFails(updateDoc(doc(as(env, 'uid-new'), 'invites', CODE), { usedBy: 'uid-new' }));
  });

  test('and not while rewriting what it grants on the way through', async () => {
    const db = as(env, 'uid-new');
    await assertFails(updateDoc(doc(db, 'invites', CODE), { usedBy: 'uid-new', role: 'manager' }));
    await assertFails(updateDoc(doc(db, 'invites', CODE), { usedBy: 'uid-new', storeId: OTHER_STORE }));
    await assertFails(updateDoc(doc(db, 'invites', CODE), { usedBy: 'uid-new', expiresAt: future() }));
    await assertFails(updateDoc(doc(db, 'invites', CODE), { usedBy: 'uid-new', createdBy: 'uid-new' }));
  });
});

describe('revoking a code', () => {
  test('a manager of that store may — it was read out to the wrong person', async () => {
    await assertSucceeds(deleteDoc(doc(as(env, MANAGER), 'invites', CODE)));
  });

  test('staff and outsiders may not', async () => {
    await assertFails(deleteDoc(doc(as(env, STAFF), 'invites', CODE)));
    await assertFails(deleteDoc(doc(as(env, OUTSIDER), 'invites', CODE)));
    await assertFails(deleteDoc(doc(anon(env), 'invites', CODE)));
  });
});
