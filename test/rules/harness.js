/**
 * Shared setup for the rules tests.
 *
 * These are the only tests in this repository that do not run under
 * `flutter test`: security rules are evaluated by Firestore, not by any code
 * here, so the only honest way to test them is to ask a real Firestore. That
 * is what the emulator is — `npm run emulate` starts one, runs the suite
 * against it and shuts it down, and its exit code is the suite's.
 *
 * Why this matters more than the line count suggests: firestore.rules is the
 * one file in the project that fails silently. A mistake in lib/ throws, shows
 * a wrong number, or fails a Dart test. A mistake here quietly lets somebody
 * read a shop's takings, and nothing anywhere says so.
 *
 * `@firebase/rules-unit-testing` is the only library that can forge an auth
 * context, which is the whole job: almost every rule in that file branches on
 * who is asking.
 */
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, Timestamp } from 'firebase/firestore';

export { assertFails, assertSucceeds };

const RULES = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

/** The store every test works against, and one that it must never reach. */
export const STORE = 'store-1';
export const OTHER_STORE = 'store-2';

export const OWNER = 'uid-owner';
export const MANAGER = 'uid-manager';
export const STAFF = 'uid-staff';
export const OUTSIDER = 'uid-outsider';

/**
 * One environment per test file, each with its own project id.
 *
 * Vitest runs files in parallel and `clearFirestore()` wipes a whole project,
 * so a single shared id means one file erasing another's fixtures mid-test.
 * The symptom is not a clean failure: rules that call `get()` on a user
 * document that has just been deleted raise an evaluation error, and writes
 * that should have been refused succeed because the state they were refused
 * against is gone. The emulator namespaces by project, so distinct ids make
 * the files independent without giving up the parallelism.
 */
export async function newTestEnv(projectId) {
  if (!projectId) throw new Error('newTestEnv needs a project id unique to this file');
  return initializeTestEnvironment({
    projectId,
    firestore: {
      rules: RULES,
      host: '127.0.0.1',
      port: 8080,
    },
  });
}

/** A Firestore handle that the rules *do* apply to. */
export const as = (env, uid) => env.authenticatedContext(uid).firestore();
export const anon = (env) => env.unauthenticatedContext().firestore();

/**
 * Writes past the rules, for arranging a test.
 *
 * Everything seeded this way is the state a test starts from, never the thing
 * it asserts — a fixture written through the rules would be testing the rules
 * twice and asserting neither.
 */
export const seed = (env, fn) =>
  env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

/** The usual cast: a store with an owner, a manager and one member of staff. */
export async function seedStore(env, { storeId = STORE } = {}) {
  await seed(env, async (db) => {
    await setDoc(doc(db, 'stores', storeId), { name: 'Test Shop', taxRate: 0 });
    await setDoc(doc(db, 'users', OWNER), user(OWNER, storeId, 'owner'));
    await setDoc(doc(db, 'users', MANAGER), user(MANAGER, storeId, 'manager'));
    await setDoc(doc(db, 'users', STAFF), user(STAFF, storeId, 'staff'));
  });
}

/** Somebody who belongs to a different store — the neighbour, not a stranger. */
export async function seedOutsider(env) {
  await seed(env, async (db) => {
    await setDoc(doc(db, 'stores', OTHER_STORE), { name: 'Other Shop' });
    await setDoc(doc(db, 'users', OUTSIDER), user(OUTSIDER, OTHER_STORE, 'owner'));
  });
}

export const user = (uid, storeId, role) => ({
  uid,
  storeId,
  role,
  email: `${uid}@example.test`,
  displayName: uid,
});

/** An order document as `submit()` writes one, minus the server timestamp. */
export const order = (overrides = {}) => ({
  orderNo: 1,
  businessDate: '2026-09-03',
  placedAt: Timestamp.fromDate(new Date('2026-09-03T12:00:00Z')),
  hourOfDay: 12,
  weekday: 4,
  channel: 'takeout',
  guestCount: 1,
  paymentMethod: 'cash',
  items: [{ itemId: 'i1', name: 'Noodles', unitPrice: 100, unitCost: 40, qty: 1 }],
  itemIds: ['i1'],
  subtotal: 100,
  discountAmount: 0,
  taxAmount: 0,
  total: 100,
  totalCost: 40,
  commissionRate: 0,
  commissionAmount: 0,
  status: 'completed',
  createdBy: STAFF,
  ...overrides,
});

export const minutesAgo = (n) =>
  Timestamp.fromDate(new Date(Date.now() - n * 60_000));
export const minutesAhead = (n) =>
  Timestamp.fromDate(new Date(Date.now() + n * 60_000));
