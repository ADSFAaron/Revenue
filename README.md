<a name="readme-top"></a>

<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/ADSFAaron/Revenue">
    <img src="assets/icon/AppLogo.png" alt="Logo" width="80" height="80">
  </a>

<h3 align="center">Revenue</h3>

  <p align="center">
    App for Revenue Statistics and Management
    <br />
    <br />
    <a href="https://github.com/ADSFAaron/Revenue/issues/new?labels=bug&template=bug-report---.md">Report Bug</a>
    ·
    <a href="https://github.com/ADSFAaron/Revenue/issues/new?labels=enhancement&template=feature-request---.md">Request Feature</a>
  </p>
</div>

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#1-clone-and-install-dependencies">1. Clone and install dependencies</a></li>
        <li><a href="#2-firebase-setup-required">2. Firebase setup (required)</a></li>
        <li><a href="#3-deploy-the-firestore-rules-and-indexes">3. Deploy the Firestore rules and indexes</a></li>
        <li><a href="#4-deploy-the-passkey-relying-party-optional">4. Deploy the passkey relying party (optional)</a></li>
        <li><a href="#5-run-the-app">5. Run the app</a></li>
      </ul>
    </li>
    <li><a href="#web-and-firebase-hosting">Web and Firebase Hosting</a></li>
    <li><a href="#building-a-release-build">Building a release build</a></li>
    <li><a href="#platform-support-status">Platform support status</a></li>
    <li>
      <a href="#project-structure">Project structure</a>
      <ul>
        <li><a href="#the-repository-layer">The repository layer</a></li>
        <li><a href="#data-model">Data model</a></li>
      </ul>
    </li>
    <li>
      <a href="#registration-and-onboarding">Registration and onboarding</a>
      <ul>
        <li><a href="#the-two-paths">The two paths</a></li>
        <li><a href="#fields-that-go-away">Fields that go away</a></li>
        <li><a href="#settings-that-are-never-asked-for">Settings that are never asked for</a></li>
        <li><a href="#invite-codes">Invite codes</a></li>
        <li><a href="#the-rules-this-needs">The rules this needs</a></li>
        <li><a href="#sign-in-methods">Sign-in methods</a></li>
        <li><a href="#passkeys">Passkeys</a></li>
      </ul>
    </li>
    <li><a href="#troubleshooting">Troubleshooting</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->
## About The Project

![Cover Image](markdown/images/Cover%20for%20Github.png)

Revenue is a Flutter app for a small restaurant to record and analyse its own sales.
It is a bookkeeping and analysis tool, **not** a point-of-sale platform: there is no
customer-facing side, no QR ordering and no platform commission. Staff tap the dishes
into their phone and submit; the value is in what the numbers say afterwards.

It covers order entry, order history, and a statistics page with charts and gauges.
Data lives in Cloud Firestore, with Firebase Authentication for sign-in.

> **Status.** The app is mid-refactor on branch `v3`. Phases 0–6 of
> [docs/refactor-plan.md](docs/refactor-plan.md) are implemented — the Firestore schema,
> the repository layer, security rules, menu editing, order entry, the statistics and
> analysis pages, Excel export, the stepped registration flow with invite codes, and
> sign-in with Google or a passkey. The one feature still outstanding is importing a
> menu from a photo, which is waiting on a decision about the recognition route. See
> [Roadmap](#roadmap) for exactly what is and is not done.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Built With

* [![Flutter][Flutter.dev]][Flutter-url]
* [![Android Studio][AndroidStudio]][AndroidStudio-url]
* [![Firebase][Firebase]][Firebase-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- GETTING STARTED -->
## Getting Started

> **A fresh clone will not run.** `lib/firebase_options.dart` is generated, not committed,
> so step 2 below is mandatory — skipping it fails the build with
> `Error: Error when reading 'lib/firebase_options.dart': No such file or directory`.

### Prerequisites

The versions below are the ones this project is known to build with. If a build breaks
after a Flutter upgrade, check these first — the Android toolchain versions in particular
are pinned in the repo and do **not** update themselves.

| Tool | Version | Where it is set |
| --- | --- | --- |
| Flutter | 3.44.8 (stable) | `flutter --version` |
| Dart | 3.12.2 | ships with Flutter |
| JDK | 21 | `java -version` |
| Gradle wrapper | 8.14.5 | `android/gradle/wrapper/gradle-wrapper.properties` |
| Android Gradle Plugin | 8.11.1 | `android/settings.gradle` |
| Kotlin | 2.2.20 | `android/settings.gradle` |
| Android min SDK | 27 | `android/app/build.gradle` |
| Android compile / target SDK | 36 | inherited from Flutter |
| Node.js + npm | any current LTS | needed only for the Firebase CLI |

Install Flutter itself from <https://docs.flutter.dev/get-started/install>, then run
`flutter doctor` and resolve anything it flags.

### 1. Clone and install dependencies

```sh
git clone https://github.com/ADSFAaron/Revenue.git
cd Revenue
flutter pub get
```

### 2. Firebase setup (required)

This project talks to the Firebase project **`revenueapp-b8849`**. Two files are needed
and **neither is committed** — you generate both with the official FlutterFire CLI.

<table>
<tr><th>File</th><th>Purpose</th></tr>
<tr><td><code>lib/firebase_options.dart</code></td><td>Read by <code>main.dart</code>; required on <b>every</b> platform</td></tr>
<tr><td><code>android/app/google-services.json</code></td><td>Read by the Gradle <code>google-services</code> plugin at build time</td></tr>
</table>

**a. Install the Firebase CLI via npm.**

```sh
npm install -g firebase-tools
firebase --version   # expect 15.x or newer
```

> Use the npm package, **not** the standalone binary from `curl -sL https://firebase.tools | bash`.
> On Apple Silicon the standalone build is an x86_64 binary that self-extracts into
> `~/.cache/firebase/tools/`; when that cache is incomplete every invocation dies with
> `ENOENT ... firebase-tools/lib/templates/hosting/init.js` and there is no clean way to
> repair it. The npm install is native arm64 and lands in a directory you own.

**b. Log in.** Access tokens expire, and a stale one still shows up in `firebase login:list`
while every API call returns 401 — so re-authenticate rather than trusting that listing:

```sh
firebase login --reauth
firebase projects:list   # revenueapp-b8849 must appear
```

**c. Install the FlutterFire CLI — version 1.4.1 or newer.**

```sh
dart pub global activate flutterfire_cli
```

> Older releases (1.0.0 in particular) cannot parse the output of Firebase CLI 15.x and
> fail with `type 'Null' is not a subtype of type 'String' in type cast`. If you hit that,
> you are on an old CLI; re-run the command above.

**d. Generate the config.**

```sh
flutterfire configure --project=revenueapp-b8849 --platforms=android,web
```

This writes `lib/firebase_options.dart` and refreshes `android/app/google-services.json`.
You need access to the `revenueapp-b8849` Firebase project for this to work.

### 3. Deploy the Firestore rules and indexes

`firestore.rules` and `firestore.indexes.json` are committed, but committing them does not
apply them. Until you deploy, a fresh project runs on whatever rules the console last had —
and the composite indexes the order queries need will not exist, so those queries fail with
a `FAILED_PRECONDITION` error containing a link to create the missing index.

> [firebase.json](firebase.json) **is committed**, as of the registration rewrite. It used
> to be git-ignored, which meant a fresh clone had neither the `firestore` nor the
> `hosting` configuration and both `firebase deploy` commands in this README aborted with
> *"Cannot understand what targets to deploy"*. The file holds only a project id, an app id
> and file paths — all values compiled into the client anyway, none of them secret. The API
> key lives in `lib/firebase_options.dart`, which stays ignored. `.firebaserc` (which pins
> the default project) is committed too.

```sh
firebase deploy --only firestore:rules,firestore:indexes --project revenueapp-b8849
```

Re-run this whenever either file changes. Index builds are asynchronous; the console shows
them as *Building* for a few minutes on a large collection.

Because the rules deny everything not explicitly matched, **the app cannot read anything
until this is deployed** on a project whose rules are still the default deny-all.

### 4. Deploy the passkey relying party (optional)

Everything except passkeys runs entirely client-side — the invite flow included, because a
Firestore client transaction is a real cross-document transaction. [functions/](functions/)
exists for the one thing that cannot: turning a verified WebAuthn assertion into a Firebase
session needs the service account key to mint a custom token.

```sh
npm --prefix functions install
firebase deploy --only functions --project revenueapp-b8849
```

Skip this and the app still works; the passkey button simply reports that the service is
not deployed. Everything else — email/password, Google, invites, orders, statistics — is
unaffected.

Three things are worth knowing before the first deploy:

* **It needs the Blaze plan.** Functions do. The usage here sits far inside the free
  quota — see [What this costs](#passkeys) — but a card has to be on file.
* **The region is `asia-east1`**, set in [functions/src/config.ts](functions/src/config.ts).
  The Dart side hard-codes the same value in `passkeyFunctionsRegion`; a callable is
  addressed by region *and* name, so if one moves the other must move with it or every call
  fails with a bare "not found".
* **`createCustomToken` needs a signer.** If deployment succeeds but sign-in fails with a
  message about IAM, grant the function's runtime service account the **Service Account
  Token Creator** role — minting a token is a signBlob call, and the default compute service
  account does not always have it.

Then enable the challenge TTL policy, once:

```sh
gcloud firestore fields ttls update expiresAt \
  --collection-group=passkeyChallenges --enable-ttl --project revenueapp-b8849
```

### 5. Run the app

Web is the current development target — it needs no device or emulator:

```sh
flutter run -d chrome
```

For Android, `flutter devices` first to confirm a device or emulator is attached, then
`flutter run`.

Register a new account to get started. The first screen asks which you are doing:
**open a new store**, which makes you its owner, or **join an existing store**, which needs
a 6-character invite code from somebody who already manages it. A new store starts with an
empty menu — add dishes under Store Settings → Edit Menu, and their categories under the 🏷
button there. Invite codes are issued from Store Settings → Staff → **Invite**.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Web and Firebase Hosting

The app is deployed as a Flutter web build on Firebase Hosting.

### Build and preview locally

```sh
flutter build web --no-tree-shake-icons
firebase emulators:start --only hosting
```

`--no-tree-shake-icons` is required: menu items store an arbitrary MaterialIcons code point
chosen at runtime in the icon picker, so the icon font cannot be shaken down to a fixed set.
Without the flag the build fails with *"Avoid non-constant invocations of IconData"*.

> On macOS the hosting emulator often reports *"unable to start on port 5000"* and moves to
> 5002 — port 5000 belongs to AirPlay Receiver. Either use the port it prints, or turn
> AirPlay Receiver off in System Settings → General → AirDrop & Handoff.

### Deploy

```sh
flutter build web --no-tree-shake-icons
firebase deploy --only hosting
```

This publishes to `https://revenueapp-b8849.web.app` (and `.firebaseapp.com`). Both are in
Firebase Auth's authorised-domains list automatically, so sign-in works with no extra setup.
Any **custom** domain has to be added manually under Authentication → Settings → Authorized
domains, or every sign-in fails with `auth/unauthorized-domain`.

To share a build without touching the live site, deploy to a preview channel instead — it
gets its own temporary URL and expires on its own:

```sh
firebase hosting:channel:deploy preview --expires 7d
```

### Caching

Flutter's web output is **not content-hashed** — `main.dart.js` has the same filename on
every build. Two obvious settings are both wrong here, and the second one is not obvious at
all:

| `Cache-Control` | What happens |
| --- | --- |
| `max-age=31536000, immutable` | Browsers that already loaded the app are pinned to that version forever. **No redeploy ever reaches them.** |
| `no-cache` | Firebase Hosting stops honouring `If-None-Match` on the file and re-sends the whole body. **Every page load re-downloads ~1 MB gzipped.** |
| `public, max-age=0, must-revalidate` ✅ | Revalidate before every use, and get a `304` with an empty body when the build has not changed. |

So [firebase.json](firebase.json) uses the third. Measured against the deployed preview
channel: a conditional request for `main.dart.js` returns `304` and 0 bytes when unchanged,
and a redeploy is still picked up on the next load. `canvaskit/` is the one exception — it
is pinned to the Flutter SDK version, so it is held for a week.

> `no-cache` and `max-age=0, must-revalidate` mean the same thing in the HTTP spec. Firebase
> Hosting's CDN does **not** treat them the same. If you change this, re-measure with
> `curl -I` and a conditional `If-None-Match` request rather than trusting the semantics.

First load is roughly **3.5 MB** of `main.dart.js`, about **1.06 MB** over the wire after
gzip. That is once per deployed version; revalidation keeps every later visit at 0 bytes.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Building a release build

Release builds currently sign with the **debug** keystore, so `flutter build apk --release`
works out of the box but produces an artifact you cannot ship to the Play Store.

To sign properly, create `android/key.properties` (git-ignored, never commit it):

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=<alias>
storeFile=<absolute path to your .jks file>
```

Then in `android/app/build.gradle`, swap the `release` build type over:

```groovy
buildTypes {
    release {
        // signingConfig signingConfigs.debug
        signingConfig = signingConfigs.release
    }
}
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Platform support status

| Platform | Status |
| --- | --- |
| Web | **Working — the current development and deployment target.** Builds, renders and initialises Firebase with no console errors; deployed via Firebase Hosting. Google sign-in and passkeys both work here with no extra client setup |
| Android | Compiles (`flutter build apk`). Not run on a device by me — none was available. Google sign-in needed its signing SHA-1 registered before Play Services would issue an ID token; that is done, see below |
| iOS | **Not configured.** The app is registered in Firebase and `ios/Runner/GoogleService-Info.plist` exists, but `firebase_options.dart` still throws `UnsupportedError` for iOS. See below. |
| Windows / macOS / Linux | Not configured |

### Android: Google sign-in and `DEVELOPER_ERROR`

Web needs no client-side setup at all. Android needs the signing certificate registered
against the app, and until it is, Google Play Services refuses with

```text
W/GoogleApiManager: ConnectionResult{statusCode=DEVELOPER_ERROR, ...}
```

which is Play Services saying it cannot match *package name + signing SHA-1* to any
registered Android OAuth client. It is a configuration error, never a code one — no
amount of Dart changes it.

Both halves are now done for `com.adsf.revenue`:

| | State |
| --- | --- |
| Android OAuth client (`client_type: 1`) | ✅ registered, bound to `com.adsf.revenue` + SHA-1 `a3a4854d…` |
| Web OAuth client (`client_type: 3`) | ✅ present in `google-services.json`, surfacing as the `default_web_client_id` string resource — this is what `google_sign_in` reads to ask for an ID token |

Diagnosing this without guessing, next time:

```sh
# What certificate does this build actually sign with?
cd android && ./gradlew signingReport        # or keytool -list -v -keystore …

# What does the project think is registered?
firebase apps:android:sha:list <appId> --project revenueapp-b8849

# Empty oauth_client here is the smoking gun.
firebase apps:sdkconfig ANDROID <appId> --project revenueapp-b8849
```

Registering a fingerprint is `firebase apps:android:sha:create <appId> <SHA>`, and
**`google-services.json` must be re-pulled afterwards** — the Android OAuth client only
appears in it once the fingerprint exists. `android/app/google-services.json` is
git-ignored, so a fresh clone needs its own copy:

```sh
firebase apps:sdkconfig ANDROID 1:984830610429:android:338f678898416549ce2794 \
  --project revenueapp-b8849 --out android/app/google-services.json
```

> ⚠️ **Release builds currently sign with the debug keystore**
> (`signingConfig signingConfigs.debug`), so the registered fingerprint is the debug one:
> SHA-1 `A3:A4:85:4D:EC:5D:52:E8:41:31:78:BF:21:DC:11:AA:05:FB:11:63`. A real release
> keystore means registering its fingerprint too — and Play App Signing re-signs uploads,
> so the fingerprint Play reports has to be registered as well or sign-in breaks only in
> production.

Passkeys on Android need neither of those — they need
[`/.well-known/assetlinks.json`](web/well-known/assetlinks.json) published, which
`firebase deploy --only hosting` does.

### Finishing iOS

To finish iOS you need CocoaPods and the `xcodeproj` Ruby gem — `flutterfire configure`
uses the latter to add `GoogleService-Info.plist` to the Xcode build phase, and aborts with
`cannot load such file -- xcodeproj (LoadError)` without it:

```sh
gem install xcodeproj cocoapods
flutterfire configure --project=revenueapp-b8849 --platforms=android,ios,web
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Project structure

```
lib/
├── main.dart                 # Entry point; Firebase init + auth-state routing
├── theme.dart                # Material theme (light/dark colour schemes)
├── login.dart / register.dart
├── sign_in_options.dart      # Google and passkey buttons, shared by both of those
├── home.dart                 # Bottom-nav shell hosting the four pages below
├── page/
│   ├── overview.dart         # Landing page: today's revenue and order count
│   ├── transaction.dart      # Today's summary + last transactions
│   ├── statistics.dart       # Charts, target gauge, Day/Week/Month, period paging
│   ├── analysis.dart         # Menu engineering, heatmap, basket analysis, prep list
│   ├── store.dart            # Store card, lifetime totals, settings entry points
│   └── addorder.dart         # Order entry
├── settings/                 # App, user, store, staff, invites, menu, order history
├── models/                   # AppUser, Store, MenuItem, Order, Invite, DailyStats, …
├── analysis/                 # The pure functions the analysis page renders
├── export/                   # Excel workbook building and saving
├── database/                 # Repository layer — the only code that talks to Firebase
└── animation/                # Shared page transitions

functions/                    # The WebAuthn relying party, and nothing else
├── src/config.ts             # RP ID, region, allowed origins, instance cap
└── src/passkeys.ts           # The six callables that make up the two ceremonies

web/well-known/assetlinks.json  # Digital Asset Links, so Android passkeys work
firestore.rules               # Security rules
firestore.indexes.json        # Composite indexes for orders, dailyStats and invites

android/app/src/main/kotlin/com/adsf/revenue/MainActivity.kt
                              # Must match the `namespace` in android/app/build.gradle
```

> The package name is `com.adsf.revenue`. If you ever rename it, `MainActivity.kt` has to
> move to the matching directory *and* have its `package` line updated — otherwise the app
> installs fine and then crashes on launch with `ClassNotFoundException`.

### The repository layer

**No widget may reference `FirebaseFirestore.instance`.** Every read and write goes
through one of the repositories in `lib/database/`, reached via the shared instances in
[repositories.dart](lib/database/repositories.dart):

| Repository | Owns |
| --- | --- |
| `UserRepository` | `users/{uid}` — profiles, roles, the store's staff list |
| `StoreRepository` | `stores/{storeId}` — name, tax, trading-day cutoff, targets, categories |
| `MenuRepository` | `stores/{storeId}/menuItems/{itemId}` |
| `OrderRepository` | `stores/{storeId}/orders/{orderId}` + counters + rollups |
| `StatsRepository` | `stores/{storeId}/dailyStats/{businessDate}` |
| `InviteRepository` | `invites/{code}` — issuing, validating and redeeming join codes |
| `AuditLogRepository` | `stores/{storeId}/auditLogs/{logId}` |
| `FeedbackRepository` | `feedback/{feedbackId}` |
| `AuthRepository` | Firebase Authentication — email/password, Google, custom tokens |
| `PasskeyRepository` | The WebAuthn ceremony and the callables in `functions/` |

The rule is about Firebase in general, not Firestore alone: `firebase_auth`,
`cloud_functions` and the `passkeys` plugin are all confined to `lib/database/` too, so
`grep -rlE 'firebase_auth|cloud_functions|package:passkeys' lib/` lists nothing outside it.
Screens deal in uids, emails and typed exceptions.

`loadSession()` resolves "signed-in user → their store" in one call; four screens used to
repeat that lookup inline.

This rule is the reason the layer exists. Firestore has no `GROUP BY`, so every new report
needs a pre-aggregated table designed for it; if that ever stops paying off, swapping the
backend is a change to one directory rather than to every screen. See §2 of
[docs/refactor-plan.md](docs/refactor-plan.md) for the trade-off in full.

### Data model

```text
users/{uid}                                 keyed by Firebase Auth uid, never by email
stores/{storeId}
  ├── menuItems/{itemId}                    stable ids; retired via isActive, never deleted
  ├── orders/{orderId}                      one document per order
  ├── dailyStats/{businessDate}             pre-aggregated rollup, yyyy-MM-dd
  ├── counters/{businessDate}               nextOrderNo, resets daily
  └── auditLogs/{logId}                     voids, order edits and price changes
invites/{code}                              single-use join codes; the code is the document id
feedback/{feedbackId}                       write-only from the app

planned, passkeys only — server-side collections, no client access at all:
passkeyCredentials/{credentialId}           public keys, keyed by credential id
passkeyChallenges/{challengeId}             single-use, 60-second lifetime
```

Amounts are whole NTD integers throughout — no decimals, no floats. Rates (`taxRate`,
`commissionRate`) are fractions: `0.05` means 5%.

#### `users/{uid}` → [app_user.dart](lib/models/app_user.dart)

| Field | Type | Notes |
| --- | --- | --- |
| `uid` | string | Same as the document id |
| `email` | string | Display only; never a lookup key |
| `displayName` | string | |
| `storeId` | string | Which store this person belongs to. Drives every security rule |
| `role` | `owner` \| `manager` \| `staff` | `owner`/`manager` may edit menu, prices and store settings |
| `createdAt` / `updatedAt` | timestamp | |

The staff list is a reverse lookup — `where('storeId', '==', id)` — not an array kept on
the store document.

`storeId` and `role` are pinned by the rules once the document exists: you may rename
yourself, but not move yourself to another store or promote yourself. A manager may change
a colleague's `role` (never their own, never the owner's, never *to* owner) from Store
Settings → Staff. A document carrying `joinedViaCode` is one that was created by redeeming
an invite, and the rules check it against that invite — see
[Registration and onboarding](#registration-and-onboarding).

#### `invites/{code}` → [invite.dart](lib/models/invite.dart)

| Field | Type | Notes |
| --- | --- | --- |
| `storeId` | string | The store being joined |
| `storeName` | string | Denormalised: whoever redeems the code cannot read `stores/{id}` yet |
| `role` | `staff` \| `manager` | Never `owner` — a store has one, and it is whoever opened it |
| `createdBy` | string | uid of the manager who issued it |
| `createdAt` / `expiresAt` | timestamp | 30 minutes |
| `usedBy` | string \| null | Written as an explicit null so the rules can compare against it |
| `usedAt` | timestamp? | |

Six upper-case alphanumerics with `0 O 1 I L` left out of the alphabet, because this code
gets read aloud across a noisy kitchen. Single use, and redeemed in one client transaction
that marks the code spent and writes `users/{uid}` together — so two people racing on the
same code produce exactly one member.

#### `stores/{storeId}` → [store.dart](lib/models/store.dart)

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | |
| `currency` / `timezone` | string | `TWD` / `Asia/Taipei` |
| `taxRate` | number | Fraction. `0` disables tax entirely |
| `taxIncluded` | bool | `true` = menu prices already contain tax (the Taiwanese default) |
| `dayCutoffHour` | int 0–23 | Trading-day rollover. Default 4 |
| `businessHours` | map | Reserved; not read yet |
| `targets` | map | `{ dailyOrders, dailyRevenue }` — feeds the statistics gauge |
| `categories` | array | `[{ id, name, sortOrder }]`, inline because every menu screen needs all of them |
| `deliveryPlatforms` | array | `[{ id, name, commissionRate }]` |
| `createdAt` / `updatedAt` | timestamp | `createdAt` is shown as "Join Time" |

There is deliberately **no `totalIncome` and no `orderIndex`**. Lifetime revenue is a
Firestore `sum()` aggregation over `dailyStats`; order numbers come from `counters`.

#### `stores/{storeId}/menuItems/{itemId}` → [menu_item.dart](lib/models/menu_item.dart)

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | |
| `categoryId` | string? | Matches an id in `stores.categories` |
| `icon` | string | MaterialIcons code point. Decimal (`"57900"`) when chosen in the picker, or the `0x`-prefixed default `"0xe56c"`; `int.tryParse` reads both |
| `sortOrder` | int | Drag-to-reorder writes consecutive values |
| `price` | int | |
| `cost` | int | Ingredient cost. `0` means *not filled in*, and is reported as unknown margin — never as 100% |
| `isActive` | bool | `false` = retired: off the order screen, still in history |
| `createdAt` / `updatedAt` | timestamp | |

#### `stores/{storeId}/orders/{orderId}` → [order.dart](lib/models/order.dart)

| Field | Type | Notes |
| --- | --- | --- |
| `orderNo` | int | Unique within its trading day, from `counters` |
| `businessDate` | string | `yyyy-MM-dd`, already shifted by `dayCutoffHour` |
| `placedAt` | timestamp | |
| `hourOfDay` | int 0–23 | Redundant against `placedAt` — see note 2 below |
| `weekday` | int 1–7 | 1 = Monday, matching `DateTime.weekday` |
| `channel` | `dine_in` \| `takeout` \| `delivery` | |
| `guestCount` | int | People on the bill, not orders |
| `deliveryPlatformId` | string? | Set only when `channel == delivery` |
| `commissionRate` / `commissionAmount` | number / int | Platform's cut, frozen at sale time |
| `paymentMethod` | `cash` \| `credit_card` \| `line_pay` \| `other` | |
| `items` | array | `[{ itemId, name, categoryId, unitPrice, unitCost, qty, lineRevenue, lineCost, note }]` |
| `itemIds` | array\<string\> | Flat list for `arrayContains` queries (basket analysis) |
| `subtotal` | int | Before discount |
| `discountAmount` / `discountReason` | int / string? | Stored; no UI yet |
| `taxAmount` | int | Contained in, or added to, `total` per `taxIncluded` |
| `total` | int | What the customer pays |
| `totalCost` | int | Sum of `lineCost` |
| `grossProfit` | int | `total - totalCost - commissionAmount` |
| `status` | `completed` \| `voided` | |
| `voidedAt` / `voidedBy` / `voidReason` | timestamp / string / string | |
| `createdBy` | string | uid |

#### `stores/{storeId}/dailyStats/{businessDate}` → [daily_stats.dart](lib/models/daily_stats.dart)

Maintained by `FieldValue.increment` inside the same transaction that writes the order, so
concurrent tills cannot lose a sale. Voiding and editing apply the same deltas in reverse.

| Field | Type |
| --- | --- |
| `businessDate` | string |
| `orderCount`, `guestCount`, `voidedCount` | int |
| `revenue`, `cost`, `discountTotal`, `taxTotal`, `commissionTotal` | int |
| `byHour` | map `"0".."23"` → `{ orders, revenue, guests }` |
| `byChannel` | map channel id → `{ orders, revenue, guests }` |
| `byPayment` | map payment id → `{ orders, revenue }` |
| `byItem` | map itemId → `{ name, qty, revenue, cost }` |
| `byCategory` | map categoryId → `{ qty, revenue, cost }` (`uncategorized` for none) |
| `updatedAt` | timestamp |

`grossProfit` is **not stored** — it is derived as `revenue - cost - commissionTotal`, so
there is one fewer field that can drift out of agreement with the others.

> `byItem` is a map, so a store with hundreds of dishes will grow this document. Under
> ~100 items it is nowhere near the 1 MB ceiling; past a few hundred, split it into a
> `dailyStats/{date}/items/{itemId}` subcollection.

#### `stores/{storeId}/counters/{businessDate}`

`{ nextOrderNo: int }`. Read and bumped inside the order transaction, which is what stops
two devices taking the same number. Resets to 1 each trading day.

#### Three decisions that should survive future edits

1. **Order lines copy in the dish name, price and cost.** A historical order freezes what
   was actually charged, so a price rise cannot retroactively rewrite last month's profit.
2. **`businessDate`, `hourOfDay` and `weekday` are stored on every order** even though
   they are derivable from `placedAt`. Firestore cannot extract an hour from a timestamp,
   so without them a time-of-day report means downloading the whole history.
3. **Orders are voided, never deleted**, and menu items are retired, never removed —
   otherwise a cancelled sale leaves no trace and a retired dish orphans its own history.

The **trading day** is not the calendar day. Each store sets `dayCutoffHour` (default 04:00,
editable in Store Settings → *Trading day starts at*); an order rung up at 02:00 counts
towards the previous day's takings, which is how a late-night kitchen actually counts.
Changing the setting only affects new orders — existing ones keep the `businessDate` they
were written with, so past reports do not silently reshuffle.

#### Access control

Rules in [firestore.rules](firestore.rules). Membership is `users/{uid}.storeId == storeId`;
managing requires `role in ['owner','manager']`.

| Path | Read | Write |
| --- | --- | --- |
| `users/{uid}` | Self, or a colleague in the same store | Create: own uid, and only in one of the two shapes below · Update: self except `storeId`/`role`, or a manager changing a colleague's `role` · Delete: never |
| `invites/{code}` | `get`: anyone · `list`: manager | Create + delete: manager · Update: spending it on yourself, once |
| `stores/{storeId}` | Member | Create: member · Update: manager · Delete: never |
| `…/menuItems` | Member | Manager |
| `…/orders` | Member | Create + update: member · **Delete: never** |
| `…/counters`, `…/dailyStats` | Member | Member |
| `…/auditLogs` | Manager | Create only |
| `feedback` | Nobody (console only) | Create only, signed in |

Membership is asserted by the `users/{uid}` document, which is written by the person it
describes — so it is not allowed to say whatever it likes. A `create` is accepted in exactly
two shapes: claiming a `storeId` that no store holds yet (the only route to `owner`), or
naming a `joinedViaCode` that the rules then `get()` and check actually grants that store
and that role, unspent and unexpired. After that `storeId` and `role` are pinned.

This replaced the store ID, which used to be the thing that granted membership: a shared
secret with no expiry and no revocation, handed to every member of staff and typed back in
by hand. See [Registration and onboarding](#registration-and-onboarding).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Registration and onboarding

> **Status: built**, except for the three items still marked open in the
> [Roadmap](#roadmap) — photo menu import, Google sign-in and passkeys, each of which
> needs infrastructure that does not exist yet. Everything else described below is what
> [register.dart](lib/register.dart), [invite_repository.dart](lib/database/invite_repository.dart)
> and [firestore.rules](firestore.rules) now do. The two paragraphs of past tense below
> describe the flow this replaced.

The person this app is for runs a small kitchen and does not want to operate software. The
registration flow that was here lost that person in the first minute, for four reasons:

1. **Six fields on one page** — email, password, confirm password, store ID, name, store name.
2. **The store ID was a 36-character UUID that a human had to type or paste.** A `Generate`
   button produced the gibberish, and the owner was then expected to pass that string to
   staff, who typed it back in.
3. **"Open a new store" and "join an existing one" were decided implicitly**, by whether the
   store ID happened to exist. The only thing telling anyone which one they were doing was a
   line of helper text.
4. **The seeded starter menu was not their menu.** They still had to delete it and type in
   sixty dishes of their own. This was the single largest barrier to getting started, and it
   arrived on day one.

### The two paths

The first screen asks which one, explicitly. No more inferring it from whether an id exists.

**Path A — open a new store** (this person becomes `owner`)

| Step | Field | Required | Notes |
| --- | --- | --- | --- |
| 1 Account | Email | ✅ | |
| | Password | ✅ | ≥6 characters (Firebase's floor). Keeps the existing show/hide toggle |
| | Display name | ✅ | Used by the staff list and by `createdBy` / `voidedBy` on orders |
| 2 Store | Store name | ✅ | The only thing about the store anyone has to type |
| 3 Menu | — | — | Primary button *Import menu from a photo*, secondary *Add dishes manually*, small link *Skip for now* |

**Path B — join an existing store**

| Step | Field | Required | Notes |
| --- | --- | --- | --- |
| 1 Invite | 6-character invite code | ✅ | **Validated before anything else is asked.** On success the screen names the store — "You are joining: <store name>" — so a mistyped code is caught here, not later |
| 2 Account | Email / password / display name | ✅ | Same as path A |

Validating the code first is deliberate: nobody should fill in a whole page and only then
discover they typed the code wrong.

### Fields that go away

| Removed | Why |
| --- | --- |
| **The store ID input and its `Generate` button** | The store id becomes an internal identifier: generated automatically, never displayed, never typed by anyone |
| **Confirm password** | There is already a show/hide toggle on the password field, which does the same job; a forgotten password has Firebase's reset flow |
| **Store name, on path B** | It comes from the invite. Staff should not have the opportunity to spell their own workplace differently from their colleagues |

### Settings that are never asked for

Registration stops asking about store configuration entirely. Everything below takes the
default it already has in code, and stays editable in Store Settings afterwards.

| Field | Default | Where the default comes from |
| --- | --- | --- |
| `taxRate` | `0` | `Store` constructor |
| `taxIncluded` | `true` | Taiwanese menu prices normally already contain tax |
| `dayCutoffHour` | `4` | `Store.defaultDayCutoffHour` |
| `targets` | `dailyOrders 100` / `dailyRevenue 20000` | `StoreTargets` |
| `currency` / `timezone` | `TWD` / `Asia/Taipei` | `Store` constructor |
| `categories` | Empty | **Changed** — no longer `MenuRepository.defaultCategories`, which is gone. Created by hand in Store Settings → Edit Menu → 🏷, or taken from an imported menu once that exists |
| `deliveryPlatforms` | Empty | Prompt for one the first time somebody picks the delivery channel |
| `businessHours` | Empty | Nothing reads it yet |

`MenuRepository.seedDefaults()` is **gone**, not merely uncalled — along with
`defaultMenu` and `defaultCategories`. An empty menu is honest; a fake menu that looks real
invites somebody to ring up a sale against 牛肉麵 that this kitchen has never sold.

Dropping the default categories left a hole: there was no way to create one, so the
category dropdown on a new dish would have stayed empty forever. Hence the category editor
in Store Settings → Edit Menu, which is not in the original design above. Deleting a
category that still has dishes in it is refused rather than leaving them pointing at a
`categoryId` nothing resolves.

### Invite codes

A new top-level collection, `invites/{code}`. The code is the document id — unique for
free, fetched with a single `get()` rather than a query, and needing no index.

| Field | Type | Notes |
| --- | --- | --- |
| `storeId` | string | The store being joined |
| `storeName` | string | Denormalised on purpose. The code is checked *before* the person belongs to any store, and at that moment they cannot read `stores/{id}` to find its name |
| `role` | `staff` \| `manager` | Chosen by whoever generates the code |
| `createdBy` | string | uid |
| `createdAt` / `expiresAt` | timestamp | 30 minutes by default |
| `usedBy` | string? | The uid that redeemed it; `null` while unused |
| `usedAt` | timestamp? | |

**Format:** six upper-case alphanumerics, with `0 O 1 I L` excluded. This code gets read
aloud across a noisy kitchen or copied onto a scrap of paper, so the characters that get
confused when spoken or written are not in the alphabet.

**Single use.** Once `usedBy` is set the code is spent. Adding three staff means generating
three codes; the generator screen supports issuing them one after another. Single-use is
both the safest option and the one that is easiest to explain to an owner.

**Redemption is atomic.** A client-side Firestore transaction marks the invite used and
writes `users/{uid}` in one commit, so two people racing on the same code produce exactly
one member. Firestore client transactions are real cross-document transactions — **this
does not need Cloud Functions**, and the project therefore does not need a Blaze plan to
ship the invite flow.

### The rules this needs

These changes ship with the invite flow, not after it — see the note under
[access control](#access-control). The shape is: a `users/{uid}` document may no longer
decide on its own which store it belongs to, or what it is allowed to do there.

**`users/{uid}` — pin `storeId` and `role`**

* `create` is allowed in exactly two shapes:
  * **Opening a store** — the `storeId` being claimed does not exist yet, in which case
    `role` may be `owner`.
  * **Joining a store** — the document carries `joinedViaCode`, and the rule `get()`s that
    invite to confirm the `storeId` matches, it has not expired, `usedBy` is still null,
    and the `role` being claimed is the one the invite grants.
* `update` requires `storeId` and `role` to equal their current values. Everything else on
  the document, `displayName` included, stays freely editable.

**`users/{uid}` — let managers change a colleague's role**

Today `update` is restricted to your own document, which means *promoting a staff member to
manager is not currently possible at all*. A second `update` clause allows
`managerOf(resource.data.storeId)` to change another member's `role`, while never touching
`storeId`, never acting on yourself, and never granting `owner`.

**`invites/{code}`**

| Operation | Allowed to |
| --- | --- |
| `create` | `managerOf(storeId)`, and only for `staff` or `manager` — never `owner` |
| `get` | **Anyone, signed in or not.** See the note below |
| `list` | `managerOf(storeId)` |
| `update` | Setting `usedBy` from null to your own uid, before `expiresAt`, changing nothing the code grants |
| `delete` | `managerOf(storeId)` |

`get` ended up more open than this section originally specified — it said "any signed-in
user". That does not survive contact with the flow: path B validates the code on its
*first* screen, before an account exists, and the whole point of validating first is that
a mistyped code is caught there rather than after a form has been filled in. So a single
`get` by exact document id is unauthenticated. Guessing a code is not a practical attack —
31⁶ ≈ 887 million codes, a handful live at a time, each dead after 30 minutes and after
one use — but the proper mitigation if that ever changes is App Check, not a rule change.
`list`, which is how you *would* enumerate other stores' codes, stays manager-only.

### Sign-in methods

`AuthRepository` is already the only thing in the app that imports `firebase_auth` —
`grep -rl 'firebase_auth' lib/` lists nothing outside `lib/database/`, and screens deal
only in uids, emails and `AuthException`. Adding a provider touches no caller.

| Method | Status | Notes |
| --- | --- | --- |
| Email / password | ✅ | Stays forever as the fallback |
| Google | ✅ | Removes three fields and fills `displayName` in automatically |
| Passkey | ✅ | See below |
| Apple | ❌ | Blocked on iOS configuration (see [Platform support status](#platform-support-status)). App Store review requires Sign in with Apple wherever another third-party sign-in is offered |

**Google takes two different routes, on purpose.** `google_sign_in_web` cannot do a
custom-button flow at all — it reports `supportsAuthenticate() == false` and *throws* if
`authenticate()` is called, offering only a Google-rendered button widget. So web goes
through `firebase_auth`'s own `signInWithPopup`, which has no such restriction and needs no
client id in `index.html`; Android goes through `google_sign_in`, which reads its client
ids out of `google-services.json`. Both land in the same
[`AuthRepository.signInWithGoogle`](lib/database/auth_repository.dart), and no screen knows
the difference.

> **Android needs two console-side things** that no amount of code substitutes for: the
> build's signing SHA-1 registered on the Android app in the Firebase console, and a
> `google-services.json` re-downloaded afterwards so it carries a `client_type: 3` web
> OAuth client. Without them `authenticate()` returns no ID token and sign-in fails with a
> configuration error. Web needs neither.

Neither button is rendered speculatively. Google is hidden where the platform has no
implementation, and the passkey button stays hidden until the device says it can actually
use one — Android below API 28 cannot, and nor can an old browser. A button whose only
possible outcome is an error is worse than no button.

### Passkeys

Firebase Authentication has no passkey provider, and `firebase_auth` has not exposed one
either — [flutterfire#17201](https://github.com/firebase/flutterfire/issues/17201) has been
open since March 2025, unassigned, labelled `blocked: firebase-sdk`. So this is a
self-hosted WebAuthn relying party, and it lives in [functions/](functions/) —
[config.ts](functions/src/config.ts) holds the handful of values that tie it to this
domain, [passkeys.ts](functions/src/passkeys.ts) is the ceremony. The client side is
[passkey_repository.dart](lib/database/passkey_repository.dart); passkeys are added and
removed under Settings → Passkeys, and used from the Login screen.

[passkeys](https://pub.dev/packages/passkeys) covers Android, iOS, macOS, **Web** and
Windows, but only the client half of the ceremony: it hands back signed data that something
trusted has to verify. Minting a Firebase custom token needs the Admin SDK's service
account key, so the function in the middle cannot be skipped.

```text
Adding a passkey:
  beginRegistration()   → server issues a challenge (single use, 60s)
  passkeys.register()   → attestation
  finishRegistration()  → verify, store the public key

Signing in:
  beginAuthentication()  → challenge
  passkeys.authenticate()→ assertion
  finishAuthentication() → verify challenge / origin / rpid / attestation /
                           signature / counter
                         → createCustomToken(uid)
  signInWithCustomToken(token)
```

Verification uses `@simplewebauthn/server`; all six checks matter, and the challenge has to
be server-generated and single-use or the whole thing is replayable.

**Storage.** Both collections sit at the top level rather than under `stores/` — at sign-in
time the user is not authenticated yet, so there is no store id to nest under.

`passkeyCredentials/{credentialId}`

| Field | Type | Notes |
| --- | --- | --- |
| `uid` | string | The Firebase Auth account this credential signs in |
| `publicKey` | string | base64 |
| `signCount` | int | Incremented on every use; a count that goes backwards means a cloned authenticator |
| `transports` | array | `usb` / `internal` / `hybrid` … |
| `deviceName` | string | So a person can tell which of their phones this is |
| `createdAt` / `lastUsedAt` | timestamp | |

The credential id is the document id because sign-in has to resolve a credential to a uid
before anybody is authenticated.

`passkeyChallenges/{challengeId}` holds `challenge`, `uid?` (null for a sign-in, which by
definition has no uid yet), `type` (registration / authentication), `createdAt` and
`expiresAt` (60 seconds). There is no `usedAt`: a challenge is **deleted** when consumed
rather than marked, and deleted *before* verification runs — a challenge that fails
verification is spent too, or a captured assertion could be retried against it until
something worked.

**Both collections are `allow read, write: if false`.** Only the Admin SDK touches them, and
the Admin SDK bypasses rules entirely. Public keys and `signCount` are the security-critical
half of WebAuthn and the client has no business reading, let alone writing, either — a
client that could write a counter could replay a cloned authenticator. Which is why
listing and removing your own passkeys goes through the `listPasskeys` and `deletePasskey`
callables instead of a Firestore query, and why what comes back is metadata only.

**Sign-in never asks who you are.** `beginPasskeyAuthentication` sends no
`allowCredentials`, because the credentials are discoverable (`residentKey: 'required'`):
the authenticator shows the person their own passkeys and reports which one they picked,
and the server resolves that credential id to a uid. So the endpoint is unauthenticated and
still leaks nothing — it cannot be asked whether a given email has an account, because it is
never told an email.

**Platform association files.** The RP ID is `revenueapp-b8849.web.app`, and Hosting serves
the file that proves the Android app belongs to it:

* `/.well-known/assetlinks.json` — Android ✅ published, in [web/well-known/](web/well-known/)
* `/.well-known/apple-app-site-association` — iOS, not written: it needs an Apple team id,
  and iOS is unconfigured anyway

> **A passkey is bound to its RP ID for good.** Moving the app to a custom domain does not
> carry passkeys with it — every one would have to be registered again. If a custom domain
> is coming, change `RP_ID` in [functions/src/config.ts](functions/src/config.ts) *before*
> anybody registers one, not after.

> **Two things blocked `/.well-known/*`, not one**, which is why the roadmap item outlived
> several attempts at it. The catch-all rewrite `"source": "**"` → `/index.html` swallowed
> the path, so [firebase.json](firebase.json) now lists the association paths as rewrites
> *before* it (Hosting applies the first rule whose pattern matches). And the `ignore` glob
> `**/.*` drops any dotted directory before upload, so a real `web/.well-known/` would
> never have been deployed at all — hence the rewrite targets, which point at
> `web/well-known/` with no leading dot. `apple-app-site-association` also gets an explicit
> `Content-Type: application/json`, which Apple requires and Hosting cannot infer from a
> file with no extension.

> ⚠️ **The published fingerprint is the debug keystore's**, because
> [android/app/build.gradle](android/app/build.gradle) still signs release builds with it
> (`signingConfig signingConfigs.debug`). The moment a real release keystore appears, two
> files need its SHA-256 or Android passkeys break with `domain-not-associated`:
> `web/well-known/assetlinks.json` wants it as colon-separated hex, and `EXPECTED_ORIGINS`
> in [functions/src/config.ts](functions/src/config.ts) wants the same bytes base64url-
> encoded. They are two spellings of one value and must never disagree.
>
> ```sh
> keytool -list -v -keystore <keystore> -alias <alias> | grep SHA256   # for assetlinks
> ```

**Passkeys are always additive, never the only way in.** Email and password stay. Losing or
replacing a phone must not lock an owner out of their own books — that is not a recoverable
failure for this audience.

**What this costs: nothing, at this scale.** Cloud Functions needs the Blaze plan, which
this project is now on. Blaze carries Spark's free quotas plus two million function
invocations a month; fifty stores at twenty sign-ins a day is around thirty thousand, some
sixty times under the ceiling. The storage side is two small collections against the same
free Firestore quota. What actually generates a surprise bill is an unbounded function, so
every one of them is capped — `MAX_INSTANCES` in
[functions/src/config.ts](functions/src/config.ts), currently 3. Set a budget alert too.

**Housekeeping.** A challenge is deleted the moment it is used, so the only ones that
accumulate are abandoned ceremonies — somebody opened the sheet and walked away. `expiresAt`
is stored as a timestamp specifically so a TTL policy can sweep those up; run this once:

```sh
gcloud firestore fields ttls update expiresAt \
  --collection-group=passkeyChallenges --enable-ttl --project revenueapp-b8849
```

It is only housekeeping. Expiry is enforced by comparing against `expiresAt` in the
function, never by the document having disappeared — TTL deletion can lag by up to 24 hours
and is not a security boundary.

**Not `corbado_auth_firebase`.** [corbado/flutter-passkeys](https://github.com/corbado/flutter-passkeys)
is a useful reference for the flow above — it is the same shape, function verifies then
mints a custom token — but its Firebase package is not the route here, for four independent
reasons: its README states the package is currently broken with no ETA; its support table
marks **Web as untested**, and Web is this project's primary platform; it still needs
Firebase Functions, so it saves nothing on infrastructure; and it deploys as a Firebase
Extension, a product being retired on 2027-03-31. It also puts the public keys on Corbado's
servers. The core `passkeys` package from the same repository has none of these problems and
is the right client-side choice.

**Sequencing.** The registration rewrite came first — passkeys are a provider bolted onto a
flow that has to exist. Then Cloud Functions, then the relying party. iOS is what remains,
and it is a platform-configuration job rather than a passkey one: the `passkeys` package
already supports it, so what is missing is an Apple team id, an app-site-association file
and the Xcode entitlement.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Troubleshooting

<details>
<summary><code>Error when reading 'lib/firebase_options.dart': No such file or directory</code></summary>

The generated Firebase config is missing. Run
[step 2](#2-firebase-setup-required) — it is not committed to the repo.
</details>

<details>
<summary><code>ClassNotFoundException: Didn't find class "com.adsf.revenue.MainActivity"</code></summary>

The app installs but crashes the instant it opens. `MainActivity.kt` is missing from
`android/app/src/main/kotlin/com/adsf/revenue/`, or its `package` declaration does not match
the `namespace` in `android/app/build.gradle`. The file should contain exactly:

```kotlin
package com.adsf.revenue

import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
}
```
</details>

<details>
<summary><code>Dependency 'androidx.core:core-ktx:X' requires Android Gradle plugin 8.9.1 or higher</code></summary>

Flutter pulled in an AndroidX version newer than the pinned AGP. Raise both plugin versions
in `android/settings.gradle` (they must move together — a new AGP needs a new Kotlin plugin):

```groovy
id "com.android.application" version "8.11.1" apply false
id 'com.android.library' version '8.11.1' apply false
id "org.jetbrains.kotlin.android" version "2.2.20" apply false
```

If Gradle then complains about its own version, bump `distributionUrl` in
`android/gradle/wrapper/gradle-wrapper.properties` too.
</details>

<details>
<summary><code>ENOENT ... firebase-tools/lib/templates/hosting/init.js</code></summary>

The standalone Firebase CLI binary has a corrupted self-extraction cache. Do not try to
repair it — install the npm package instead (`npm install -g firebase-tools`) and make sure
its install directory precedes `/usr/local/bin` in your `PATH`. Verify which one you are
running with `which firebase`.
</details>

<details>
<summary><code>type 'Null' is not a subtype of type 'String' in type cast</code> during <code>flutterfire configure</code></summary>

The FlutterFire CLI is too old for your Firebase CLI. Run `dart pub global activate flutterfire_cli`
to get 1.4.1 or newer.
</details>

<details>
<summary><code>Failed to list Firebase projects</code> / HTTP 401</summary>

Your OAuth token has expired. `firebase login:list` will still cheerfully print your email —
ignore it and check `firebase-debug.log`, which shows the token refresh returning 400. Fix
with `firebase login --reauth`.
</details>

<details>
<summary>A verbose <code>pub_log.txt</code> appears in <code>~/.pub-cache/log/</code></summary>

Usually **not** an error. After a Dart SDK upgrade the cached `flutterfire` snapshot is
stale; the launcher script detects exit code 253, re-runs the command with `-v` to rebuild
the snapshot, and that verbose transcript is what gets written to the log. Check its last
lines — if they read `Built flutterfire_cli:flutterfire`, it succeeded and the real failure
is somewhere after it.
</details>

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ROADMAP -->
## Roadmap

Tracked against the phases in [docs/refactor-plan.md](docs/refactor-plan.md).

**Phase 0 — foundations** ✅

* [x] Firestore security rules and composite indexes
* [x] Repository layer; no widget touches `FirebaseFirestore.instance`
* [x] Registration keys `users/{uid}` by Auth uid, creates the store and seeds a menu

**Phase 1 — menu** ✅

* [x] `menuItems` subcollection with stable ids
* [x] Optional ingredient `cost` per dish
* [x] Categories, drag-to-reorder, retire/restore instead of delete

**Phase 2 — orders** ✅

* [x] One document per order
* [x] Order numbers from a per-day counter, allocated in a transaction
* [x] Channel (dine-in / takeout / delivery + platform commission), guest count,
      payment method and tax all actually persisted
* [x] `dailyStats` rollups maintained in the same transaction as the order
* [x] Void an order instead of deleting it
* [x] Trading-day cutoff, editable per store
* [x] Overview, Transaction and Store pages on real data; the placeholder
      "Last Transactions" row and hard-coded growth badges are gone

**Phase 3 — statistics** ✅

* [x] Target gauge reads the store's daily target
* [x] Day / Week / Month tabs over real date ranges
* [x] Back / forward arrows to page through periods
* [x] Comparison against the previous period
* [x] Weekday × hour heatmap
* [x] Item ranking with a date range and sorting

**Phase 4 — analysis** ✅

* [x] Menu engineering matrix (needs `cost` filled in to say anything)
* [x] Basket analysis (which dishes are ordered together)
* [x] Prep forecasting

**Phase 5 — export and audit** ✅

* [x] Excel export
* [x] `auditLogs` UI

**Phase 6 — registration and onboarding**

Design in [Registration and onboarding](#registration-and-onboarding).

* [x] Split registration into steps, with "open a store" and "join a store" as an explicit choice
* [x] Retire the store ID field and its `Generate` button — the id becomes internal
* [x] `invites/{code}` collection, manager-side code generator, redemption in a client transaction
* [x] Lock `storeId` and `role` in the rules; let managers change a colleague's role
* [x] Stop calling `MenuRepository.seedDefaults()` at registration
* [x] A category editor, which dropping the seeded categories made necessary —
      Store Settings → Edit Menu → 🏷
* [x] `/.well-known/*` exception in the hosting rewrite (was blocking passkeys on both
      mobile platforms)
* [x] Google sign-in — `signInWithPopup` on web, `google_sign_in` on Android
* [x] A Cloud Functions relying party in [functions/](functions/), then passkeys
* [ ] Import a menu from a photo (needs the recognition route settled first)
* [ ] Apple sign-in (blocked on iOS configuration)

**Not tied to a phase**

* [ ] Dark mode apply
* [ ] Language change / international language support
* [ ] Material You theme apply
* [ ] Notification to "add transaction" at a set time
* [ ] iOS configuration

See the [open issues](https://github.com/ADSFAaron/Revenue/issues) for a full list of proposed features (and known issues).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->
## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".
Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Top contributors

<a href="https://github.com/ADSFAaron/Revenue/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=ADSFAaron/Revenue" alt="contrib.rocks image" />
</a>

<!-- LICENSE -->
## License

Distributed under the MIT License. See `LICENSE.txt` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTACT -->
## Contact

Project Link: [https://github.com/ADSFAaron/Revenue](https://github.com/ADSFAaron/Revenue)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[Flutter.dev]: https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white
[Flutter-url]: https://flutter.dev/
[AndroidStudio]: https://img.shields.io/badge/Android_Studio-3DDC84?style=for-the-badge&logo=android-studio&logoColor=white
[AndroidStudio-url]: https://developer.android.com/studio
[Firebase]: https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black
[Firebase-url]: https://firebase.google.com/
