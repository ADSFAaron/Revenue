# Changelog

Notable changes to Revenue. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The number in brackets is the Android `versionCode` — the one Google Play
compares, and the one shown after the version in **Store → Account & app →
Version**.

## [3.0.0] (3) — unreleased

The release that made the app usable by somebody who is not its author: an
offline queue so a bad connection cannot stop a shift, delivery orders and
their commission included in the figures, roles that behave, and a manual that
explains where every number comes from.

### Added

- **Offline order queue.** Orders rung up without a connection are held on the
  device and sent when it returns; a bar counts what is still waiting.
- **Import orders from a delivery platform's statement**, so a day that sold
  well on a platform no longer reads as a quiet day.
- **Payment methods**, configurable and ordered. Reports break the takings down
  by them.
- **Delivery platforms with commission rates**, taken off gross profit —
  without them a delivery order books as pure revenue.
- **In-app manual** (*Store → How this works*), with the arithmetic behind every
  figure. Reached from the Store tab, and from the Insights and Reports app
  bars for the chapters they concern.
- **Google Play in-app updates.** The Version row says when a newer build is
  published and downloads it in the background; the till keeps working, and the
  restart happens when the shopkeeper is ready.
- **Demand profile and prep list** — orders averaged by weekday and hour, with
  how many of that weekday the average is drawn from.
- **Menu item aliases**, so an imported statement's dish names match the menu.
- **Larger text sizes** are handled without the layouts breaking.
- **[AGPL-3.0 licence](LICENSE)**, a [security policy](SECURITY.md), and
  [contribution guidelines](CONTRIBUTING.md). The repository was public with no
  licence at all before this.

### Security

Found while checking what still stood between this build and a Play upload.
Everything here was live behind an app that was about to be published.

- **App Check is enforced on every Cloud Function.** The app has produced
  attestation tokens since App Check was added, and nothing on the server ever
  looked at one — so the token proved nothing and `importMenuFromPhotos`, the
  only call here that spends money per invocation, was reachable by anything
  holding an ID token.
- **An invite code no longer reveals a store to an unauthenticated reader.**
  `invites` allowed `get: if true` so that registration could check a code
  before an account existed. Anyone holding a stray code could read `storeId` —
  the id every other security rule is keyed on — without signing in. The check
  moved to the `checkInvite` callable, which App Check gates and which answers
  with the store's name and role only.
- **An order's `createdAt` must now be the server's clock.** The five-minute
  window in which staff may correct their own order was measured against a
  timestamp nothing validated, so a client writing its own `createdAt` a year
  ahead held an unbounded licence to rewrite its own orders without a manager.
- **Audit entries are signed.** `byUid` was whatever the client put there, on
  the one collection whose entire purpose is recording who did something.
- **Order-number counters cannot be wound back**, which is how the same order
  number gets issued twice, and neither counters nor a day's totals can be
  deleted.
- **Feedback submissions are shape- and size-checked.** `create: if signedIn()`
  accepted any document of any size under any field name.
- **Deleting an account requires a recent sign-in.** The call takes the store,
  every order in it and every colleague's login, and a till's session token
  lives on a counter all day.

### Changed

- **The release build signs with the upload keystore** when `android/key.properties`
  is present, and the debug keys when it is not. It used to be hard-coded to the
  debug keys with the real config commented out below — so shipping meant
  remembering to edit a file, and forgetting meant an upload Play rejects after
  the version code has been spent.
- **R8 is on** for release builds, with `android/app/proguard-rules.pro`.
- **The Play listing is English** (`play/listing-en-US.md`). A Traditional
  Chinese listing was written first and is kept, unused, at
  `play/listing-zh-TW.md` — the app's interface is English throughout, and a
  Chinese listing in front of an English app is the mismatch that earns a
  one-star review. It goes back into service when Revenue is localised.
- **A privacy policy** at `web/privacy.html`, linked from *Store → Account &
  app*. Google Play requires one for every app; this one describes what is
  actually stored, including that menu photographs go to Google's Gemini API
  and are not retained.
- **The Store tab is regrouped** into Setup, Records and You. Order history,
  order import and change history moved out of Store Settings onto the tab
  itself, one level shallower — an order's detail is now two taps from the tab
  rather than three.
- **User Settings and App Settings merged** into *Account & app*, with Log out
  moved in beside Delete account instead of sitting loose among navigation rows.
- **Settings rows now predict themselves.** A chevron means a screen opens;
  rows that edit in place no longer wear one.
- **Settings are role-aware.** Manager-only rows render read-only with a
  padlock, keeping their value visible, instead of opening a dialog that fails
  on save. Menu, categories, payment methods and delivery platforms stay
  readable for everyone and drop their editing controls.
- The setup checklist is no longer shown to store assistants — every row on it
  led somewhere they cannot act.
- Version bumped from `1.0.0+1`, which had never moved.

### Fixed

- **The offline banners said the opposite of what the app does.** Both of them
  — the shell's and the one on Add Order — still read "orders cannot be rung
  up" and "it cannot be saved until the connection is back". That was true
  before the offline queue and was never updated when the queue shipped in this
  same release: `_queueOffline` has been putting new orders on the device, with
  the time they were rung up at, since it was written. So the one screen where
  somebody needed to know the feature exists was telling them it does not — and
  contradicting the store listing, which sells offline ordering as a headline.
  Found while taking the Play screenshot for it. An **edit** still cannot be
  saved offline, which is why the strip now distinguishes the two rather than
  giving one answer to two questions.
- **Every external link was broken on Android 11 and later.** *Source code* and
  the Play-listing fallback resolve a link by asking which app handles it, and
  since Android 11 that question returns nothing without a `<queries>`
  declaration — so both rows did nothing at all, silently. The AGPL obliges this
  app to make its source reachable, and it had not been since the day it
  targeted API 30.
- **The app asked for the microphone.** `camera_android_camerax` merges
  `RECORD_AUDIO` in for video recording; Revenue photographs a menu and has no
  audio path at all. Also merged in, and equally unwanted: `READ_EXTERNAL_STORAGE`,
  which no manifest declares — the merger invents it as soon as any library in
  the graph asks to write shared storage.
- **The app hid itself from devices without a camera.** The manifest declared
  `android.hardware.camera` optional, but CameraX merges in
  `android.hardware.camera.any` with no `required` attribute, which means
  *required*. Two different feature names, and the merged manifest is what Play
  reads.
- **`READ_INTERNAL_STORAGE`, which is not an Android permission**, along with
  two real storage permissions and `requestLegacyExternalStorage`. Nothing in
  the app ever requested any of them; the workbook export writes to the app's
  own directory, which has needed no permission since Android 10.
- **Device backup is off.** Auto Backup and device-to-device transfer would copy
  the offline order queue onto a second device, which then sends it — the same
  takings booked twice, with nothing on screen to explain it.
- The feedback dialog had no Cancel, and validated an empty message *after*
  closing — so the error named a field that was no longer on screen.
- The Store tab had two entries leading to the same Store Settings screen.
