/**
 * Cloud Functions for Revenue.
 *
 * Two things live here, and both are here for the same reason: they need a
 * credential the app cannot be trusted to hold.
 *
 *   passkeys.ts     Firebase Authentication has no passkey provider, and
 *                   minting a custom token from a verified WebAuthn assertion
 *                   needs the service account key.
 *   menu_import.ts  Reading a menu off a photograph needs a model API key,
 *                   and a key shipped inside an APK is a key anybody can read
 *                   out of it.
 *
 * Everything else the app does — including the invite-code flow, which is a
 * real cross-document Firestore transaction — runs client-side and needs no
 * server.
 */

import { initializeApp } from "firebase-admin/app";

initializeApp();

export {
  beginPasskeyRegistration,
  finishPasskeyRegistration,
  beginPasskeyAuthentication,
  finishPasskeyAuthentication,
  listPasskeys,
  deletePasskey,
} from "./passkeys.js";

export { importMenuFromPhotos } from "./menu_import.js";

export { deleteAccount } from "./account.js";
