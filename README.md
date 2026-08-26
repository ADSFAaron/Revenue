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
        <li><a href="#4-run-the-app">4. Run the app</a></li>
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
        <li><a href="#passkeys-designed-not-built">Passkeys (designed, not built)</a></li>
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

> **Status.** The app is mid-refactor on branch `v3`. Phases 0–2 of
> [docs/refactor-plan.md](docs/refactor-plan.md) are implemented — the Firestore schema,
> the repository layer, security rules, menu editing and order entry are all on the new
> design. Phases 3–5 (real Day/Week/Month ranges, menu engineering, Excel export) are
> not. See [Roadmap](#roadmap) for exactly what is and is not done.

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

> ⚠️ **`firebase.json` is git-ignored** (line 51 of `.gitignore`), so a fresh clone has
> neither the `firestore` nor the `hosting` configuration, and both `firebase deploy`
> commands in this README abort with *"Cannot understand what targets to deploy"*.
>
> Consider removing that line: the file holds only a project id, an app id and file paths —
> all values that are compiled into the client anyway, none of them secret. Until then,
> every machine has to recreate the `firestore` and `hosting` blocks by hand.
> `.firebaserc` (which pins the default project) *is* committed.

```sh
firebase deploy --only firestore:rules,firestore:indexes --project revenueapp-b8849
```

Re-run this whenever either file changes. Index builds are asynchronous; the console shows
them as *Building* for a few minutes on a large collection.

Because the rules deny everything not explicitly matched, **the app cannot read anything
until this is deployed** on a project whose rules are still the default deny-all.

### 4. Run the app

Web is the current development target — it needs no device or emulator:

```sh
flutter run -d chrome
```

For Android, `flutter devices` first to confirm a device or emulator is attached, then
`flutter run`.

Register a new account to get started. Entering a **new** store ID creates the store, makes
you its owner and seeds a starter menu; entering an **existing** store ID joins that store
as staff, and the store name field is ignored.

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
| Web | **Working — the current development and deployment target.** Builds, renders and initialises Firebase with no console errors; deployed via Firebase Hosting |
| Android | Builds and runs. Not re-verified since the Phase 0–2 refactor — no device or emulator was available |
| iOS | **Not configured.** The app is registered in Firebase and `ios/Runner/GoogleService-Info.plist` exists, but `firebase_options.dart` still throws `UnsupportedError` for iOS. See below. |
| Windows / macOS / Linux | Not configured |

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
├── home.dart                 # Bottom-nav shell hosting the four pages below
├── page/
│   ├── overview.dart         # Landing page: today's revenue and order count
│   ├── transaction.dart      # Today's summary + last transactions
│   ├── statistics.dart       # Charts and target gauge (Day only — see Roadmap)
│   ├── store.dart            # Store card, lifetime totals, settings entry points
│   └── addorder.dart         # Order entry
├── settings/                 # App, user, store, staff, menu, order history
├── models/                   # AppUser, Store, MenuItem, Order, OrderDraft, DailyStats
├── database/                 # Repository layer — the only code that talks to Firestore
└── animation/                # Shared page transitions

firestore.rules               # Security rules
firestore.indexes.json        # Composite indexes for the orders subcollection

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
| `FeedbackRepository` | `feedback/{feedbackId}` |

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
  └── auditLogs/{logId}                     reserved; no UI yet
invites/{code}                              planned; the code is the document id
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
| `users/{uid}` | Self, or a colleague in the same store | Self only |
| `stores/{storeId}` | Member | Create: member · Update: manager · Delete: never |
| `…/menuItems` | Member | Manager |
| `…/orders` | Member | Create + update: member · **Delete: never** |
| `…/counters`, `…/dailyStats` | Member | Member |
| `…/auditLogs` | Manager | Create only |
| `feedback` | Nobody (console only) | Create only, signed in |

> Membership is asserted by the `users/{uid}` document, and a store ID is currently the
> thing that grants it — a shared secret with no expiry and no revocation, handed to every
> member of staff. [Registration and onboarding](#registration-and-onboarding) replaces it
> with an invite flow and tightens these rules in the same change. The two are one piece of
> work rather than two, and the ordering matters: the rules go in with the invite flow, not
> after it.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Registration and onboarding

> **Status: specification only.** Nothing in this section is implemented. The current
> [register.dart](lib/register.dart) still asks for all six fields on one page and still
> seeds the starter menu. This section is the agreed design for replacing it.

The person this app is for runs a small kitchen and does not want to operate software. The
registration flow as it stands loses that person in the first minute, for four reasons:

1. **Six fields on one page** — email, password, confirm password, store ID, name, store name.
2. **The store ID is a 36-character UUID that a human has to type or paste.** There is a
   `Generate` button that produces the gibberish, and the owner is then expected to pass
   that string to staff, who type it back in.
3. **"Open a new store" and "join an existing one" are decided implicitly**, by whether the
   store ID happens to exist. The only thing telling anyone which one they are doing is a
   line of helper text.
4. **The seeded starter menu is not their menu.** They still have to delete it and type in
   sixty dishes of their own. This is the single largest barrier to getting started, and it
   arrives on day one.

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
| `categories` | Taken from the imported menu; empty if skipped | **Changed** — no longer `MenuRepository.defaultCategories` |
| `deliveryPlatforms` | Empty | Prompt for one the first time somebody picks the delivery channel |
| `businessHours` | Empty | Nothing reads it yet |

`MenuRepository.seedDefaults()` is **no longer called at registration**. An empty menu is
honest; a fake menu that looks real invites somebody to ring up a sale against 牛肉麵 that
this kitchen has never sold.

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
| `create` | `managerOf(storeId)` |
| `read` | Any signed-in user — at validation time they are not yet a member of anything |
| `update` | Setting `usedBy` from null to your own uid, before `expiresAt` |
| `delete` | `managerOf(storeId)` |

### Sign-in methods

`AuthRepository` is already the only thing in the app that imports `firebase_auth` —
`grep -rl 'firebase_auth' lib/` lists nothing outside `lib/database/`, and screens deal
only in uids, emails and `AuthException`. Adding a provider touches no caller.

| Order | Method | Notes |
| --- | --- | --- |
| 1 | Email / password | Current behaviour. Stays forever as the fallback |
| 2 | Google | Removes three fields and fills `displayName` in automatically |
| 3 | Passkey | See below |
| 4 | Apple | Blocked on iOS configuration (see [Platform support status](#platform-support-status)). App Store review requires Sign in with Apple wherever another third-party sign-in is offered |

### Passkeys (designed, not built)

Firebase Authentication has no passkey provider, and `firebase_auth` has not exposed one
either — [flutterfire#17201](https://github.com/firebase/flutterfire/issues/17201) has been
open since March 2025, unassigned, labelled `blocked: firebase-sdk`. So this is a
self-hosted WebAuthn relying party.

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

`passkeyChallenges/{challengeId}` holds `challenge`, `uid?`, `type`
(registration / authentication), `expiresAt` (60 seconds) and `usedAt`.

**Both collections must be `allow read, write: if false`.** Only the Admin SDK touches
them. Public keys and `signCount` are the security-critical half of WebAuthn and the client
has no business reading, let alone writing, either.

**Platform association files.** The RP ID is the Firebase Hosting domain, and Hosting
serves both files:

* `/.well-known/assetlinks.json` — Android
* `/.well-known/apple-app-site-association` — iOS (no extension, served as `application/json`)

> The hosting rewrite in [firebase.json](firebase.json) is currently `"source": "**"` →
> `/index.html`, which swallows `/.well-known/*` along with everything else. It needs an
> exception, or neither association file is reachable and passkeys fail on both platforms.

**Passkeys are always additive, never the only way in.** Email and password stay. Losing or
replacing a phone must not lock an owner out of their own books — that is not a recoverable
failure for this audience.

**What this costs.** Cloud Functions requires the Blaze plan, which the project is not on
(there is no `functions/` directory today). Blaze carries the same free quotas as Spark plus
two million function invocations a month; fifty stores at twenty sign-ins a day is around
thirty thousand, some sixty times under the ceiling. The real barrier is putting a card on
file, not the bill. Set a budget alert and `maxInstances` on every function — an unbounded
function is the thing that actually generates a surprise.

If a card is genuinely not an option, the relying party can live on Cloudflare Workers
instead: 100,000 requests/day free with no card, `@simplewebauthn/server` runs there, and a
Firebase custom token is just an RS256 JWT signed with the service account key, which Web
Crypto can do without the Admin SDK. The cost is a second cloud provider to deploy and
debug. Photo-based menu import will want a server too, so whichever way this goes, the two
features share the bill.

**Not `corbado_auth_firebase`.** [corbado/flutter-passkeys](https://github.com/corbado/flutter-passkeys)
is a useful reference for the flow above — it is the same shape, function verifies then
mints a custom token — but its Firebase package is not the route here, for four independent
reasons: its README states the package is currently broken with no ETA; its support table
marks **Web as untested**, and Web is this project's primary platform; it still needs
Firebase Functions, so it saves nothing on infrastructure; and it deploys as a Firebase
Extension, a product being retired on 2027-03-31. It also puts the public keys on Corbado's
servers. The core `passkeys` package from the same repository has none of these problems and
is the right client-side choice.

**Sequencing.** The registration rewrite comes first — passkeys are a provider bolted onto a
flow that has to exist. Then Cloud Functions, then the relying party, then iOS.

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

**Phase 3 — statistics** — not started

* [x] Target gauge reads the store's daily target
* [ ] Day / Week / Month tabs over real date ranges (all three currently show the day)
* [ ] Back / forward arrows to page through periods (disabled for now)
* [ ] Comparison against the previous period
* [ ] Weekday × hour heatmap
* [ ] Item ranking with a date range and sorting

**Phase 4 — analysis** — not started

* [ ] Menu engineering matrix (needs `cost` filled in)
* [ ] Basket analysis (which dishes are ordered together)
* [ ] Prep forecasting

**Phase 5 — export and audit** — not started

* [ ] Excel export (the button currently only logs)
* [ ] `auditLogs` UI

**Phase 6 — registration and onboarding** — specified, not started

Design in [Registration and onboarding](#registration-and-onboarding).

* [ ] Split registration into steps, with "open a store" and "join a store" as an explicit choice
* [ ] Retire the store ID field and its `Generate` button — the id becomes internal
* [ ] `invites/{code}` collection, manager-side code generator, redemption in a client transaction
* [ ] Lock `storeId` and `role` in the rules; let managers change a colleague's role
* [ ] Stop calling `MenuRepository.seedDefaults()` at registration
* [ ] Import a menu from a photo (needs the recognition route settled first)
* [ ] Google sign-in
* [ ] Cloud Functions or a Workers relying party, then passkeys
* [ ] `/.well-known/*` exception in the hosting rewrite (blocks passkeys on both mobile platforms)

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
