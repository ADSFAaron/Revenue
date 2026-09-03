/**
 * The collections no client has any business in, and the catch-all underneath
 * everything else.
 */
import { beforeAll, afterAll, beforeEach, describe, test } from 'vitest';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, getDocs, collection, serverTimestamp } from 'firebase/firestore';
import {
  newTestEnv, as, anon, seed, seedStore,
  assertFails, assertSucceeds, STORE, OWNER, STAFF,
} from './harness.js';

let env;
beforeAll(async () => { env = await newTestEnv('rules-closed'); });
afterAll(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await seedStore(env);
});

describe('passkeys — closed to every client, in both directions', () => {
  test('credentials cannot be read or written, not even your own', async () => {
    await seed(env, (db) => setDoc(doc(db, 'passkeyCredentials', 'c1'), { userId: STAFF, counter: 0 }));
    const db = as(env, STAFF);
    await assertFails(getDoc(doc(db, 'passkeyCredentials', 'c1')));
    await assertFails(getDocs(collection(db, 'passkeyCredentials')));
    // A client that could write a counter could replay a cloned authenticator;
    // one that could write a public key could sign in as anybody.
    await assertFails(updateDoc(doc(db, 'passkeyCredentials', 'c1'), { counter: 99 }));
    await assertFails(setDoc(doc(db, 'passkeyCredentials', 'c2'), { userId: STAFF }));
    await assertFails(deleteDoc(doc(db, 'passkeyCredentials', 'c1')));
  });

  test('challenges are worse, and equally closed', async () => {
    await seed(env, (db) => setDoc(doc(db, 'passkeyChallenges', 'ch1'), { challenge: 'x' }));
    const db = as(env, STAFF);
    await assertFails(getDoc(doc(db, 'passkeyChallenges', 'ch1')));
    await assertFails(setDoc(doc(db, 'passkeyChallenges', 'ch2'), { challenge: 'y' }));
  });
});

describe('feedback — write only, and shaped', () => {
  const message = (over = {}) => ({
    storeId: STORE, feedback: 'The reports page is slow.',
    version: '3.0.0', build: '3', uid: STAFF, timestamp: serverTimestamp(), ...over,
  });
  const f = (db, id = 'f1') => doc(db, 'feedback', id);

  test('a signed-in person sends one', async () => {
    await assertSucceeds(setDoc(f(as(env, STAFF)), message()));
  });

  test('signed out sends nothing', async () => {
    await assertFails(setDoc(f(anon(env)), message()));
  });

  test('nobody reads it back — it is answered from the console', async () => {
    await seed(env, (db) => setDoc(f(db), { ...message(), timestamp: null }));
    await assertFails(getDoc(f(as(env, OWNER))));
    await assertFails(getDocs(collection(as(env, OWNER), 'feedback')));
  });

  test('a report cannot be filed under somebody else\'s name', async () => {
    await assertFails(setDoc(f(as(env, STAFF)), message({ uid: OWNER })));
  });

  test('an empty message is not feedback', async () => {
    await assertFails(setDoc(f(as(env, STAFF)), message({ feedback: '' })));
  });

  test('4000 characters is the ceiling — the alternative is a megabyte per call', async () => {
    await assertSucceeds(setDoc(f(as(env, STAFF)), message({ feedback: 'a'.repeat(4000) })));
    await assertFails(setDoc(f(as(env, STAFF), 'f2'), message({ feedback: 'a'.repeat(4001) })));
  });

  test('unexpected fields are refused, so the shape stays the shape', async () => {
    await assertFails(setDoc(f(as(env, STAFF)), { ...message(), payload: 'x'.repeat(1000) }));
  });

  test('the server clock stamps it, so the console list is in order', async () => {
    await assertFails(setDoc(f(as(env, STAFF)), message({ timestamp: new Date(0) })));
  });

  test('it cannot be edited or withdrawn after the fact', async () => {
    await seed(env, (db) => setDoc(f(db), { ...message(), timestamp: null }));
    await assertFails(updateDoc(f(as(env, STAFF)), { feedback: 'never mind' }));
    await assertFails(deleteDoc(f(as(env, STAFF))));
  });
});

describe('everything else', () => {
  test('a collection no rule mentions is closed', async () => {
    const db = as(env, OWNER);
    await assertFails(getDoc(doc(db, 'somethingElse', 'x')));
    await assertFails(setDoc(doc(db, 'somethingElse', 'x'), { a: 1 }));
    await assertFails(setDoc(doc(db, 'stores', STORE, 'unknownSubcollection', 'x'), { a: 1 }));
  });
});
