# Security policy

This app holds a shop's takings. A hole in it is somebody's books, so please
report one privately rather than opening an issue.

## Reporting a vulnerability

Use GitHub's private reporting: go to the repository's **Security** tab and
choose **Report a vulnerability**. That opens a draft advisory only you and the
maintainers can see.

> Maintainers: this needs **Settings → Code security → Private vulnerability
> reporting** switched on for the button to appear.

Please include what you were able to do, and the account or role you did it
from — "a store assistant can read another shop's orders" is immediately
actionable in a way that "the rules look weak" is not.

Expect an acknowledgement within a few days. Please give a fix a reasonable
window before publishing.

## In scope

* **[`firestore.rules`](firestore.rules)** — this is the whole security model.
  Every client talks straight to Firestore, so anything these rules permit is
  permitted, full stop. Reads or writes across a store boundary, or past a
  role, are the findings that matter most.
* **[`functions/`](functions)** — the callables hold credentials the app must
  not: the WebAuthn relying party, the menu-import key, account deletion.
* **The client**, where it stores or leaks something it should not.

## Not vulnerabilities

These come up, and are answered here so nobody spends time on them:

* **The Firebase config is public.** `google-services.json` is no longer
  committed — it is a build input now, not a source file — but the same values
  are in every shipped APK and in the built web bundle, and this repository's
  history still carries the copy that used to be tracked. That is fine.
  Firebase API keys are project identifiers, not credentials; Google documents
  them as public. Access is decided by `firestore.rules`, by Authentication,
  and now by App Check — never by knowing the key.
* **The security rules are readable.** They are meant to be. A model that only
  holds while nobody has read it is not a model.

If you can show one of these is wrong in practice — an enumeration that is
cheaper than the arithmetic suggests, say — that *is* a finding, and it is a
welcome one.

## Known gaps

Stated plainly rather than left to be discovered:

* **`dailyStats` is written by the till, not by a server.** Every figure in it
  arrives as a `FieldValue.increment` from the same client transaction that
  writes the order, and a rule sees the result rather than the delta — so a
  member of staff who writes to Firestore directly, rather than through the
  app, can move a day's revenue without touching an order. The rules stop the
  day being deleted and stop it being filed under the wrong date; they cannot
  make the arithmetic honest. The fix is a Firestore trigger that recomputes
  the rollup server-side, which is written down at the end of
  [`firestore.rules`](firestore.rules) rather than half-done. Until then:
  `orders` are the books and cannot be forged, `dailyStats` is a cache of them
  and can be, and anything that matters is recomputed from `orders` — which
  [`lib/export/statistics_workbook.dart`](lib/export/statistics_workbook.dart)
  already does.

## Recently closed

Named because earlier versions of this file invited reports about them:

* **`invites/{code}` allowed an unauthenticated `get`.** It now requires
  sign-in. The pre-account check that needed it goes through the `checkInvite`
  callable in [`functions/src/invites.ts`](functions/src/invites.ts), which
  answers with the store's name and the role only — `storeId` never leaves the
  server.
* **App Check was not enforced.** The app had been sending attestation tokens
  for some time and nothing on the server looked at one. Every callable now
  sets `enforceAppCheck`.
