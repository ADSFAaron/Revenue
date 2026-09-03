/**
 * `users/{uid}` — the document every other rule in the file trusts.
 *
 * It is written by the person it describes, which is why it may not say
 * whatever it likes: a document that could name any store and any role would
 * make `memberOf()` and `managerOf()` decorative.
 */
import { beforeAll, afterAll, beforeEach, describe, test } from 'vitest';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, getDocs, query, collection, where, Timestamp } from 'firebase/firestore';
import {
  newTestEnv, as, anon, seed, seedStore, seedOutsider, user,
  assertFails, assertSucceeds, STORE, OTHER_STORE, OWNER, MANAGER, STAFF, OUTSIDER,
} from './harness.js';

let env;
beforeAll(async () => { env = await newTestEnv('rules-users'); });
afterAll(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await seedStore(env);
  await seedOutsider(env);
});

describe('reading', () => {
  test('you can read your own document', async () => {
    await assertSucceeds(getDoc(doc(as(env, STAFF), 'users', STAFF)));
  });

  test('you can read a colleague in the same store — this is the staff list', async () => {
    await assertSucceeds(getDoc(doc(as(env, STAFF), 'users', MANAGER)));
  });

  test('you cannot read somebody in another store', async () => {
    await assertFails(getDoc(doc(as(env, STAFF), 'users', OUTSIDER)));
  });

  test('signed out reads nothing', async () => {
    await assertFails(getDoc(doc(anon(env), 'users', STAFF)));
  });

  test('the staff list query is scoped to your own store', async () => {
    const db = as(env, STAFF);
    await assertSucceeds(getDocs(query(collection(db, 'users'), where('storeId', '==', STORE))));
    await assertFails(getDocs(query(collection(db, 'users'), where('storeId', '==', OTHER_STORE))));
    // Unscoped: would return every user of every store.
    await assertFails(getDocs(collection(db, 'users')));
  });
});

describe('opening a store', () => {
  test('claiming a store id nobody holds makes you its owner', async () => {
    await assertSucceeds(
      setDoc(doc(as(env, 'uid-new'), 'users', 'uid-new'), user('uid-new', 'store-fresh', 'owner')));
  });

  test('you cannot declare yourself owner of a store that already exists', async () => {
    await assertFails(
      setDoc(doc(as(env, 'uid-new'), 'users', 'uid-new'), user('uid-new', STORE, 'owner')));
  });

  test('you cannot write somebody else\'s user document', async () => {
    await assertFails(
      setDoc(doc(as(env, 'uid-new'), 'users', OWNER), user(OWNER, 'store-fresh', 'owner')));
  });

  test('the uid field has to match the document id', async () => {
    await assertFails(
      setDoc(doc(as(env, 'uid-new'), 'users', 'uid-new'), user('somebody-else', 'store-fresh', 'owner')));
  });

  test('joining without an invite is not a way in', async () => {
    await assertFails(
      setDoc(doc(as(env, 'uid-new'), 'users', 'uid-new'), user('uid-new', STORE, 'staff')));
  });
});

describe('joining with an invite', () => {
  const CODE = 'ABC123';
  const invite = (over = {}) => ({
    storeId: STORE, storeName: 'Test Shop', role: 'staff',
    createdBy: MANAGER, usedBy: null,
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 30 * 60_000)),
    createdAt: Timestamp.now(), ...over,
  });
  const joining = (over = {}) => ({ ...user('uid-new', STORE, 'staff'), joinedViaCode: CODE, ...over });

  test('a valid code lets you in at the role it grants', async () => {
    await seed(env, (db) => setDoc(doc(db, 'invites', CODE), invite()));
    await assertSucceeds(setDoc(doc(as(env, 'uid-new'), 'users', 'uid-new'), joining()));
  });

  test('a staff code cannot be redeemed into a manager account', async () => {
    await seed(env, (db) => setDoc(doc(db, 'invites', CODE), invite({ role: 'staff' })));
    await assertFails(
      setDoc(doc(as(env, 'uid-new'), 'users', 'uid-new'), joining({ role: 'manager' })));
  });

  test('a code for one store cannot be used to join another', async () => {
    await seed(env, (db) => setDoc(doc(db, 'invites', CODE), invite({ storeId: OTHER_STORE })));
    await assertFails(setDoc(doc(as(env, 'uid-new'), 'users', 'uid-new'), joining()));
  });

  test('a spent code is spent', async () => {
    await seed(env, (db) => setDoc(doc(db, 'invites', CODE), invite({ usedBy: 'somebody' })));
    await assertFails(setDoc(doc(as(env, 'uid-new'), 'users', 'uid-new'), joining()));
  });

  test('an expired code is refused', async () => {
    await seed(env, (db) => setDoc(doc(db, 'invites', CODE), invite({
      expiresAt: Timestamp.fromDate(new Date(Date.now() - 60_000)) })));
    await assertFails(setDoc(doc(as(env, 'uid-new'), 'users', 'uid-new'), joining()));
  });

  test('naming a code that does not exist is refused', async () => {
    await assertFails(setDoc(doc(as(env, 'uid-new'), 'users', 'uid-new'), joining()));
  });

  test('no invite can grant ownership — a store has exactly one owner', async () => {
    await seed(env, (db) => setDoc(doc(db, 'invites', CODE), invite({ role: 'owner' })));
    await assertFails(
      setDoc(doc(as(env, 'uid-new'), 'users', 'uid-new'), joining({ role: 'owner' })));
  });
});

describe('changing a user document afterwards', () => {
  test('you may edit your own display name', async () => {
    await assertSucceeds(updateDoc(doc(as(env, STAFF), 'users', STAFF), { displayName: 'New Name' }));
  });

  test('you may not promote yourself', async () => {
    await assertFails(updateDoc(doc(as(env, STAFF), 'users', STAFF), { role: 'manager' }));
    await assertFails(updateDoc(doc(as(env, MANAGER), 'users', MANAGER), { role: 'owner' }));
  });

  test('you may not move yourself to another store', async () => {
    await assertFails(updateDoc(doc(as(env, STAFF), 'users', STAFF), { storeId: OTHER_STORE }));
  });

  test('a manager may change a colleague\'s role', async () => {
    await assertSucceeds(updateDoc(doc(as(env, MANAGER), 'users', STAFF), { role: 'manager' }));
  });

  test('a manager may not make anybody an owner', async () => {
    await assertFails(updateDoc(doc(as(env, MANAGER), 'users', STAFF), { role: 'owner' }));
  });

  test('a manager may not touch the owner', async () => {
    await assertFails(updateDoc(doc(as(env, MANAGER), 'users', OWNER), { role: 'staff' }));
  });

  test('staff may not change anybody\'s role', async () => {
    await assertFails(updateDoc(doc(as(env, STAFF), 'users', MANAGER), { role: 'staff' }));
  });

  test('a manager of another store may not reach in', async () => {
    await assertFails(updateDoc(doc(as(env, OUTSIDER), 'users', STAFF), { role: 'manager' }));
  });

  test('a role change may not smuggle other edits through with it', async () => {
    await assertFails(updateDoc(doc(as(env, MANAGER), 'users', STAFF), {
      role: 'manager', email: 'attacker@example.test' }));
  });
});

describe('deletion', () => {
  test('nobody may delete a user document, not even their own', async () => {
    await assertFails(deleteDoc(doc(as(env, STAFF), 'users', STAFF)));
    await assertFails(deleteDoc(doc(as(env, OWNER), 'users', STAFF)));
  });
});

describe('membership is currently permanent — see docs/auth-and-operator-plan.md §5.1', () => {
  test('a departed colleague cannot be removed or moved out of the store', async () => {
    const db = as(env, MANAGER);
    await assertFails(deleteDoc(doc(db, 'users', STAFF)));
    await assertFails(updateDoc(doc(db, 'users', STAFF), { storeId: null }));
    await assertFails(updateDoc(doc(db, 'users', STAFF), { storeId: OTHER_STORE }));
  });

  /**
   * The hook the planned `active` flag can hang on, discovered by writing this
   * test rather than assumed: `managerChangingSomeoneElsesRole` pins role,
   * storeId, uid, email and displayName, and says nothing at all about any
   * other field. So a manager may add one.
   *
   * Good news for the fix — `memberOf()` gaining an `active` check needs no
   * change to the write rule. Less good as it stands: a manager may write
   * *anything* onto a colleague's document, including a field some future rule
   * decides to trust. When `active` lands, this rule should name the fields a
   * manager may change instead of naming the ones they may not.
   */
  test('but a manager may add arbitrary fields to a colleague — including `active`', async () => {
    await assertSucceeds(updateDoc(doc(as(env, MANAGER), 'users', STAFF), { active: false }));
    await assertSucceeds(updateDoc(doc(as(env, MANAGER), 'users', STAFF), { anythingAtAll: 'yes' }));
  });

  test('and that door is only open to a manager of the same store', async () => {
    await assertFails(updateDoc(doc(as(env, STAFF), 'users', MANAGER), { active: false }));
    await assertFails(updateDoc(doc(as(env, OUTSIDER), 'users', STAFF), { active: false }));
  });
});
