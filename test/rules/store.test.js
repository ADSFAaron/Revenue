/**
 * `stores/{storeId}` and its menu.
 *
 * The split that matters: everybody who works there reads, only a manager
 * writes. A price is a manager-level fact because `OrderLine` freezes it onto
 * every order that follows.
 */
import { beforeAll, afterAll, beforeEach, describe, test } from 'vitest';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import {
  newTestEnv, as, anon, seed, seedStore, seedOutsider,
  assertFails, assertSucceeds, STORE, OWNER, MANAGER, STAFF, OUTSIDER,
} from './harness.js';

let env;
beforeAll(async () => { env = await newTestEnv('rules-store'); });
afterAll(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await seedStore(env);
  await seedOutsider(env);
  await seed(env, (db) =>
    setDoc(doc(db, 'stores', STORE, 'menuItems', 'i1'), { name: 'Noodles', price: 100, cost: 40 }));
});

describe('the store document', () => {
  test('any member reads it', async () => {
    await assertSucceeds(getDoc(doc(as(env, STAFF), 'stores', STORE)));
  });

  test('an outsider does not', async () => {
    await assertFails(getDoc(doc(as(env, OUTSIDER), 'stores', STORE)));
    await assertFails(getDoc(doc(anon(env), 'stores', STORE)));
  });

  test('settings are manager-level — tax rate, trading-day cutoff, commissions', async () => {
    await assertSucceeds(updateDoc(doc(as(env, MANAGER), 'stores', STORE), { taxRate: 5 }));
    await assertSucceeds(updateDoc(doc(as(env, OWNER), 'stores', STORE), { taxRate: 5 }));
    await assertFails(updateDoc(doc(as(env, STAFF), 'stores', STORE), { taxRate: 5 }));
    await assertFails(updateDoc(doc(as(env, OUTSIDER), 'stores', STORE), { taxRate: 5 }));
  });

  test('no client deletes a store — that goes through deleteAccount', async () => {
    await assertFails(deleteDoc(doc(as(env, OWNER), 'stores', STORE)));
  });
});

describe('the menu', () => {
  test('staff read it, because the till has to price an order', async () => {
    await assertSucceeds(getDoc(doc(as(env, STAFF), 'stores', STORE, 'menuItems', 'i1')));
  });

  test('staff do not write it', async () => {
    await assertFails(updateDoc(doc(as(env, STAFF), 'stores', STORE, 'menuItems', 'i1'), { price: 1 }));
    await assertFails(setDoc(doc(as(env, STAFF), 'stores', STORE, 'menuItems', 'i2'), { name: 'X', price: 1 }));
    await assertFails(deleteDoc(doc(as(env, STAFF), 'stores', STORE, 'menuItems', 'i1')));
  });

  test('a manager writes it', async () => {
    await assertSucceeds(updateDoc(doc(as(env, MANAGER), 'stores', STORE, 'menuItems', 'i1'), { price: 120 }));
    await assertSucceeds(deleteDoc(doc(as(env, MANAGER), 'stores', STORE, 'menuItems', 'i1')));
  });

  test('another store\'s manager reaches nothing', async () => {
    await assertFails(getDoc(doc(as(env, OUTSIDER), 'stores', STORE, 'menuItems', 'i1')));
    await assertFails(updateDoc(doc(as(env, OUTSIDER), 'stores', STORE, 'menuItems', 'i1'), { price: 1 }));
  });
});
