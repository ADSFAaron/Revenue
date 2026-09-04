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

describe('removing somebody from the store — docs/auth-and-operator-plan.md §5.1', () => {
  /** Removal as the app performs it. */
  const remove = (uid, by = MANAGER) =>
    updateDoc(doc(as(env, by), 'users', uid), { active: false });

  test('a manager may remove a colleague, and put them back', async () => {
    await assertSucceeds(remove(STAFF));
    await assertSucceeds(updateDoc(doc(as(env, MANAGER), 'users', STAFF), { active: true }));
  });

  test('the owner is not removable — a store has exactly one', async () => {
    await assertFails(remove(OWNER));
  });

  test('you cannot remove yourself', async () => {
    await assertFails(remove(MANAGER, MANAGER));
  });

  test('staff cannot remove anybody', async () => {
    await assertFails(remove(MANAGER, STAFF));
  });

  test('a manager of another store cannot reach in', async () => {
    await assertFails(remove(STAFF, OUTSIDER));
  });

  test('`active` has to be a boolean', async () => {
    await assertFails(updateDoc(doc(as(env, MANAGER), 'users', STAFF), { active: 'no' }));
  });

  /**
   * The door this file found before `active` existed: the rule pinned five
   * fields and said nothing about the rest, so a manager could write anything
   * onto a colleague — which stopped being harmless the moment a rule started
   * trusting one of those fields.
   */
  test('a manager may change a role or a membership, and nothing else', async () => {
    await assertFails(updateDoc(doc(as(env, MANAGER), 'users', STAFF), { anythingAtAll: 'yes' }));
    await assertFails(updateDoc(doc(as(env, MANAGER), 'users', STAFF), { displayName: 'Renamed' }));
  });

  test('deleting or moving somebody out of the store is still refused', async () => {
    const db = as(env, MANAGER);
    await assertFails(deleteDoc(doc(db, 'users', STAFF)));
    await assertFails(updateDoc(doc(db, 'users', STAFF), { storeId: null }));
    await assertFails(updateDoc(doc(db, 'users', STAFF), { storeId: OTHER_STORE }));
  });
});

describe('what a removed member may still do', () => {
  beforeEach(async () => {
    await seed(env, (db) =>
      setDoc(doc(db, 'users', STAFF), { ...user(STAFF, STORE, 'staff'), active: false }));
  });

  test('they can read their own document — the app has to be able to say why', async () => {
    await assertSucceeds(getDoc(doc(as(env, STAFF), 'users', STAFF)));
  });

  test('they cannot restore themselves', async () => {
    await assertFails(updateDoc(doc(as(env, STAFF), 'users', STAFF), { active: true }));
  });

  test('they may still correct their own name', async () => {
    await assertSucceeds(updateDoc(doc(as(env, STAFF), 'users', STAFF), { displayName: 'Still Me' }));
  });

  test('the store, its colleagues and its books are closed to them', async () => {
    const db = as(env, STAFF);
    await assertFails(getDoc(doc(db, 'stores', STORE)));
    await assertFails(getDoc(doc(db, 'users', MANAGER)));
    await assertFails(getDocs(query(collection(db, 'users'), where('storeId', '==', STORE))));
    await assertFails(getDocs(collection(db, 'stores', STORE, 'orders')));
    await assertFails(getDocs(collection(db, 'stores', STORE, 'menuItems')));
  });

  test('a manager who has been removed cannot act as one', async () => {
    await seed(env, (db) =>
      setDoc(doc(db, 'users', MANAGER), { ...user(MANAGER, STORE, 'manager'), active: false }));
    await assertFails(updateDoc(doc(as(env, MANAGER), 'users', STAFF), { role: 'manager' }));
  });
});

describe('documents written before `active` existed', () => {
  test('a missing flag means a member, not a stranger', async () => {
    // seedStore writes no `active` field at all — every other test in this
    // file depends on that reading as true, and this says so out loud.
    await assertSucceeds(getDoc(doc(as(env, STAFF), 'stores', STORE)));
    await assertSucceeds(getDoc(doc(as(env, STAFF), 'users', MANAGER)));
  });
});
