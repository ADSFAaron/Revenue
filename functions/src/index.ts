/**
 * Cloud Functions for Revenue.
 *
 * There is exactly one reason this directory exists: Firebase Authentication
 * has no passkey provider, and minting a custom token from a verified WebAuthn
 * assertion needs the service account key. Everything else the app does —
 * including the invite-code flow, which is a real cross-document Firestore
 * transaction — runs client-side and needs no server.
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
