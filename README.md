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
    <li>
      <a href="#importing-a-menu-from-a-photo">Importing a menu from a photo</a>
      <ul>
        <li><a href="#why-a-vision-model-rather-than-ocr">Why a vision model rather than OCR</a></li>
        <li><a href="#what-is-asked-of-the-model-and-what-is-not">What is asked of the model, and what is not</a></li>
        <li><a href="#nothing-is-written-until-somebody-says-yes">Nothing is written until somebody says yes</a></li>
        <li><a href="#writing">Writing</a></li>
        <li><a href="#what-it-is-allowed-to-cost">What it is allowed to cost</a></li>
      </ul>
    </li>
    <li><a href="#5-app-check">App Check</a></li>
    <li><a href="#troubleshooting">Troubleshooting</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#found-a-security-hole">Security</a></li>
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

> **Status.** The app is mid-refactor on branch `v3`. Phases 0–7 of
> [docs/refactor-plan.md](docs/refactor-plan.md) are implemented — the Firestore schema,
> the repository layer, security rules, menu editing, order entry, the statistics and
> analysis pages, Excel export, the stepped registration flow with invite codes, sign-in
> with Google or a passkey, and importing a menu from a photograph. What remains is
> platform work rather than features: iOS configuration, and Apple sign-in behind it. See
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

> **`<PROJECT_ID>`, `<ANDROID_APP_ID>` and the rest are placeholders.** The real
> values for the hosted deployment are not in this repository — they live in
> `docs/deployment.local.md`, which is git-ignored. If you are running your own
> Firebase project, substitute your own throughout; `flutterfire configure`
> writes most of them for you.

This project talks to your own Firebase project. Two files are needed
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
firebase projects:list   # <PROJECT_ID> must appear
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
flutterfire configure --project=<PROJECT_ID> --platforms=android,web
```

This writes `lib/firebase_options.dart` and refreshes `android/app/google-services.json`.
You need access to the `<PROJECT_ID>` Firebase project for this to work.

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
firebase deploy --only firestore:rules,firestore:indexes --project <PROJECT_ID>
```

Re-run this whenever either file changes. Index builds are asynchronous; the console shows
them as *Building* for a few minutes on a large collection.

Because the rules deny everything not explicitly matched, **the app cannot read anything
until this is deployed** on a project whose rules are still the default deny-all.

### 4. Deploy the Cloud Functions (optional)

Almost everything runs entirely client-side — the invite flow included, because a Firestore
client transaction is a real cross-document transaction. [functions/](functions/) exists
for the two things that cannot, and both are there for the same reason: they need a
credential the app must not be trusted to hold.

| Function | Why it cannot live in the app |
| --- | --- |
| The passkey relying party | Turning a verified WebAuthn assertion into a Firebase session needs the service account key to mint a custom token |
| Photo menu import | Reading a menu off a photograph needs a model API key, and a key shipped inside an APK is a key anybody can read out of it |

```sh
npm --prefix functions install
firebase functions:secrets:set GEMINI_API_KEY   # paste a key from aistudio.google.com/apikey
firebase deploy --only functions --project <PROJECT_ID>
```

Skip the whole step and the app still works; the passkey button and the menu importer each
report that their service is not deployed. Everything else — email/password, Google,
invites, orders, statistics — is unaffected.

**The secret is not optional if you deploy at all.** `defineSecret` binds `GEMINI_API_KEY`
to the menu import function, and the CLI refuses the deploy outright rather than deploying
the rest without it:

```
Error: In non-interactive mode but have no value for the secret GEMINI_API_KEY
```

Setting the secret needs the **Secret Manager API** enabled on the project. The CLI enables
Cloud Build, Artifact Registry and Extensions by itself but not this one, so a first deploy
on a fresh project stops with a 403 naming `secretmanager.googleapis.com`. Enable it
[here](https://console.cloud.google.com/apis/library/secretmanager.googleapis.com), or with
`gcloud services enable secretmanager.googleapis.com`, then set the secret and deploy.

`firebase deploy --dry-run` runs every check up to the point of writing anything, which is
the cheapest way to find out which of these is missing before spending a real deploy on it.

Three things are worth knowing before the first deploy:

* **It needs the Blaze plan.** Functions do. The usage here sits far inside the free
  quota — see [What this costs](#passkeys) — but a card has to be on file.
* **The region is `asia-east1`**, set in [functions/src/config.ts](functions/src/config.ts).
  The Dart side hard-codes the same value in `passkeyFunctionsRegion` and in
  `menuImportFunctionsRegion`; a callable is addressed by region *and* name, so if one
  moves the others must move with it or every call fails with a bare "not found".
* **`createCustomToken` needs a signer.** If deployment succeeds but sign-in fails with a
  message about IAM, grant the function's runtime service account the **Service Account
  Token Creator** role — minting a token is a signBlob call, and the default compute service
  account does not always have it.

* **Menu import needs a Gemini API key**, set as the `GEMINI_API_KEY` secret above and
  bound to that one function so the passkey functions never see it. The call is
  `POST /v1beta/models/{model}:generateContent` under a response schema, against
  `gemini-3.7-flash` falling back to `gemini-3.6-flash` and `gemini-3.5-flash`. A menu
  photo measured 1,345 prompt + 1,014 output tokens — well under a New Taiwan dollar, and
  it is a once-per-store action, not a per-order one.
* **Timeouts are raised on both sides.** Recognition takes 20–40 seconds for one photo and
  longer for four; the function's default is 60 seconds and the Dart client's is 70. Both
  are lifted to five minutes (`TIMEOUT_SECONDS` in
  [functions/src/menu_import.ts](functions/src/menu_import.ts), `menuImportTimeout` in
  [lib/database/menu_import_repository.dart](lib/database/menu_import_repository.dart)).
  Left at the defaults, a two-page menu fails on the client while the server is still
  working — which looks like a bug and costs the call anyway.

Then enable the challenge TTL policy, once:

```sh
gcloud firestore fields ttls update expiresAt \
  --collection-group=passkeyChallenges --enable-ttl --project <PROJECT_ID>
```

### 5. App Check

`main.dart` activates App Check before the first Firestore read. Without it
configured on the project side nothing breaks — activation failure is caught
and logged — but the protection is not there either.

**What it is for.** The security rules decide what a signed-in *account* may
do. Nothing else decides whether the caller is this app at all, and since
registration takes seconds and this project has no email verification, "holds a
valid account" is not a barrier. App Check is the other half: Play Integrity has
Google vouch for the installation, so a script holding a working login gets no
token. It matters most for the menu import, the one call here that spends real
money per invocation.

**Register one Android app and one web app — not the others.**

| Register | Provider |
| --- | --- |
| `com.adsf.revenue` — appId `<ANDROID_APP_ID>` | Play Integrity |
| The web app — appId `<WEB_APP_ID>` | reCAPTCHA Enterprise |

The project also carries several apps left over from earlier iterations
(`com.example.adsf.revenue`, `com.adsf.revenueStatistics`, and some unfinished
iOS entries). **They do not need deleting.** App Check is an allow-list: only a
registered app can obtain a token, so once enforcement is on, everything you did
not register is refused by that fact alone. Deleting a Firebase app is
irreversible and takes its config with it, so check the Play Console for a live
listing before removing any of them.

**Enable monitoring first, enforcement later.** The console shows the split
between verified and unverified requests. Enforce only once verified traffic is
effectively all of it — switching it on early locks out every copy of the app
that has not been updated yet.

**Local development.** Debug builds use the debug provider, which mints a token
against a local secret rather than attesting anything. The token is printed to
the log on first run:

```
D/com.google.firebase.appcheck: Enter this debug secret into the allow list…
```

Paste it into **App Check → the Android app → ⋮ → Manage debug tokens**. It is
per machine and per install, so a new laptop or a wiped emulator needs a new
one.

**Web needs a site key**, which is per project and not a secret, but is not
something this repository should guess. Web activation is skipped when it is
absent:

```bash
flutter build web --dart-define=APP_CHECK_RECAPTCHA_KEY=6Lc...
```

> **Play Integrity attests apps that came from Google Play.** A sideloaded APK,
> or a release build made on a machine with no `android/key.properties` (which
> falls back to the debug keys), cannot be attested — use the debug provider for
> those. Once the app is on Play, Play App Signing re-signs it, and the SHA-256
> to register in Firebase and in
> [assetlinks.json](web/well-known/assetlinks.json) is Google's, taken from the
> Play Console. See [Building a release build](#building-a-release-build).
>
> App Check is **enforced** on every callable (`CALLABLE_OPTIONS` in
> [functions/src/config.ts](functions/src/config.ts)), so this is not optional
> configuration any more: a build that cannot produce a token is a build whose
> function calls are refused. Register a debug token per machine, and pass
> `--dart-define=APP_CHECK_RECAPTCHA_KEY=…` to every web build.

### 6. Run the app

Web is the development and demo surface — it needs no device or emulator, so it is the
fastest way to see a change. Android and iOS are what actually ship:

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

### The Passkeys web SDK is not optional

[web/passkeys/bundle.js](web/passkeys/bundle.js) is vendored into this repo, and
[web/index.html](web/index.html) loads it **before** the Flutter bootstrap:

```html
<script src="passkeys/bundle.js"></script>
```

Remove either one and the web build does not merely lose passkeys — **it does not start
at all.** The page shows the loading spinner, the engine initialises, the spinner is
removed, and then a blank `#eae9e4` screen. Nothing renders, on every route, for every
user, signed in or not.

The reason is in `passkeys_web`'s plugin registration
([passkeys_web-2.10.0/lib/passkeys_web.dart](https://pub.dev/packages/passkeys_web)):

```dart
static void registerWith([Object? registrar]) {
  PasskeysPlatform.instance = PasskeysWeb();

  try {
    final _ = window['PasskeyAuthenticator'];   // never throws
  } catch (_) {
    debugPrint('Error: Passkeys Web SDK not loaded. ...');
    window.close();
  }

  init();   // @JS('PasskeyAuthenticator.init')
}
```

The guard is broken. Reading a missing property off `window` in JavaScript yields
`undefined` — it does not throw — so the `catch` never runs and execution falls through to
`init()`, which dereferences `undefined`:

```text
Error: Null check operator used on a null value
TypeError: Cannot read properties of undefined (reading 'init')
```

That runs inside `registerPlugins()`, which Flutter's generated web entrypoint calls
*before* `main()`. So the failure is not scoped to the passkey button, or to the Login
screen, or to anything the user did. It is the whole application, before the first frame.

The bundle is taken from the release the package's own error message points at
([flutter-passkeys 2.4.0](https://github.com/corbado/flutter-passkeys/releases/download/2.4.0/bundle.js),
13.5 KB). It is the only release that ships the asset, and the seven functions it exports —
`init`, `register`, `login`, `cancelCurrentAuthenticatorOperation`, `hasPasskeySupport`,
`isUserVerifyingPlatformAuthenticatorAvailable`, `isConditionalMediationAvailable` — are
exactly the seven `passkeys_web` 2.10.0 binds in its `interop.dart`. It is committed rather
than fetched from a CDN so that a build never depends on a third-party host being up, and
so no third party gets to run script on the auth origin.

> Upgrading `passkeys` is the moment to re-check this. If a future `passkeys_web` binds a
> function the vendored bundle does not export, the symptom is the same blank page — so
> after any bump, load the built app once and confirm it renders before deploying.

### Deploy

```sh
flutter build web --no-tree-shake-icons
firebase deploy --only hosting
```

This publishes to `https://<PROJECT_ID>.web.app` (and `.firebaseapp.com`). Both are in
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

The release build signs with the upload keystore when one is configured and with the
debug keys when one is not, so `flutter build apk --release` works out of the box on a
fresh clone and a machine that has a key produces a shippable artifact without editing
any file. There is nothing to switch over.

Create the keystore, once, and keep it somewhere it cannot be lost — **Play ties the app
to it permanently, and there is no way to re-key an app whose upload key is gone except
asking Google to reset it**:

```sh
keytool -genkey -v -keystore ~/revenue-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then `android/key.properties` (git-ignored, never commit it):

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=<absolute path to your .jks file>
```

`android/app/build.gradle` picks it up by the file's existence:

```groovy
signingConfig keystorePropertiesFile.exists()
    ? signingConfigs.release
    : signingConfigs.debug
```

> ⚠️ **Changing the signing key changes three other files, and they must agree.**
> The SHA-256 of the signing certificate appears in three encodings, and a build where
> they disagree fails only in the places that are hardest to test — Google sign-in and
> passkeys, in production, on somebody else's phone:
>
> 1. `functions/src/config.ts` → `EXPECTED_ORIGINS` (base64url, no padding)
> 2. `web/well-known/assetlinks.json` → `sha256_cert_fingerprints` (colon-separated hex)
> 3. The Firebase console → the Android app's SHA-1, for Google sign-in
>
> And with **Play App Signing** — which is mandatory for new apps — the certificate that
> matters is **Google's**, not your upload key. Take it from Play Console → Release →
> Setup → App signing after the first upload, and register that. Registering the upload
> key instead is the mistake that looks fine in every local build and breaks the moment
> the app is installed from Play.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Platform support status

| Platform | Status |
| --- | --- |
| Web | **Working — the current development and deployment target.** Builds, renders and initialises Firebase with no console errors; deployed via Firebase Hosting. Google sign-in and passkeys both work here with no extra client setup |
| Android | **Working, and the target for release.** Builds and runs; Google sign-in has its signing SHA-1 registered (see below), passkeys work against the Digital Asset Links file, and Play in-app updates are wired into Store → Account & app → Version. Signs with the upload keystore when `android/key.properties` is present — see [Building a release build](#building-a-release-build) |
| iOS | **Not configured.** The app is registered in Firebase and `ios/Runner/GoogleService-Info.plist` exists, but `firebase_options.dart` still throws `UnsupportedError` for iOS. See below. |
| Windows | Compiles; the plugin registrant is generated and checked in. Not a supported target — the Play update flow and App Check are Android-only, and the Version row falls back to plain text there |
| macOS / Linux | Not configured |

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
firebase apps:android:sha:list <appId> --project <PROJECT_ID>

# Empty oauth_client here is the smoking gun.
firebase apps:sdkconfig ANDROID <appId> --project <PROJECT_ID>
```

Registering a fingerprint is `firebase apps:android:sha:create <appId> <SHA>`, and
**`google-services.json` must be re-pulled afterwards** — the Android OAuth client only
appears in it once the fingerprint exists. `android/app/google-services.json` is
git-ignored, so a fresh clone needs its own copy:

```sh
firebase apps:sdkconfig ANDROID <ANDROID_APP_ID> \
  --project <PROJECT_ID> --out android/app/google-services.json
```

> ⚠️ **The registered fingerprint is still the debug one**, SHA-1 `<DEBUG_SHA1>`, because
> no `android/key.properties` exists yet and the build falls back to the debug keys. An
> upload keystore means registering its fingerprint too — and Play App Signing re-signs
> uploads, so the fingerprint Play reports has to be registered as well or sign-in breaks
> only in production.

Passkeys on Android need neither of those — they need
[`/.well-known/assetlinks.json`](web/well-known/assetlinks.json) published, which
`firebase deploy --only hosting` does.

### Finishing iOS

To finish iOS you need CocoaPods and the `xcodeproj` Ruby gem — `flutterfire configure`
uses the latter to add `GoogleService-Info.plist` to the Xcode build phase, and aborts with
`cannot load such file -- xcodeproj (LoadError)` without it:

```sh
gem install xcodeproj cocoapods
flutterfire configure --project=<PROJECT_ID> --platforms=android,ios,web
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Project structure

```
lib/
├── main.dart                 # Entry point; Firebase init + auth-state routing
├── theme.dart                # Material theme (light/dark colour schemes)
├── login.dart / register.dart
├── sign_in_options.dart      # Google and passkey buttons, shared by both of those
├── home.dart                 # Bottom-nav shell hosting the four tabs below
├── page/
│   ├── transaction.dart      # "Today" — the day so far, last orders, setup checklist
│   ├── analysis.dart         # "Insights" — menu engineering, heatmap, basket analysis
│   ├── statistics.dart       # "Reports" — charts, target gauge, Day/Week/Month, export
│   ├── store.dart            # "Store" — store card, then Setup / Records / You
│   └── addorder.dart         # Order entry (pushed, not a tab)
├── settings/                 # Everything behind the Store tab
│   ├── store_settings.dart           # Name, trading day, tax, targets, staff, menu
│   ├── store_settings_edit_menu.dart # Dishes, prices, costs; photo import lives here
│   ├── store_settings_history_order.dart / store_setting_history_order_detail.dart
│   ├── store_import_orders.dart      # Reads a delivery platform's statement in
│   ├── store_settings_audit_log.dart # Change history (managers only)
│   ├── account_settings.dart         # Profile, sign-in, appearance, version, log out
│   ├── app_update.dart               # Play in-app updates; the Version row's brain
│   └── user_manual.dart              # "How this works" — the in-app manual
├── widgets/                  # Shared UI: SettingTile, EmptyState, ErrorView, charts,
│                             #   money formatting, offline/pending-order bars
├── models/                   # AppUser, Store, MenuItem, Order, Invite, DailyStats, …
├── analysis/                 # The pure functions the Insights page renders
├── export/                   # Excel workbook building and saving
├── database/                 # Repository layer — the only code that talks to Firebase
└── animation/                # Shared page transitions

functions/                    # The jobs that need a credential the app must not hold
├── src/config.ts             # RP ID, region, allowed origins, instance cap
├── src/passkeys.ts           # The six callables that make up the two ceremonies
├── src/menu_import.ts        # Reads a menu off a photo. Recognises only — writes nothing
├── src/model_ladder.ts       # Which model that import tries, and in what order
└── src/account.ts            # Account deletion, including closing a store

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
| `categories` | Empty | **Changed** — no longer `MenuRepository.defaultCategories`, which is gone. Created by hand in Store Settings → Edit Menu → 🏷, or taken from the section headings of [an imported menu](#importing-a-menu-from-a-photo) |
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

> **Web carries a hard prerequisite.** `passkeys_web` needs a JavaScript SDK loaded from
> `index.html`, and if it is absent the plugin takes the whole app down at startup rather
> than degrading. See
> [The Passkeys web SDK is not optional](#the-passkeys-web-sdk-is-not-optional).

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

**Platform association files.** The RP ID is `<PROJECT_ID>.web.app`, and Hosting serves
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

> ⚠️ **The published fingerprint is the debug keystore's**, because no
> `android/key.properties` exists yet and
> [android/app/build.gradle](android/app/build.gradle) falls back to the debug keys
> without one. The moment an upload keystore appears — and again once Play App Signing
> reports Google's certificate — two files need that SHA-256 or Android passkeys break
> with `domain-not-associated`:
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
  --collection-group=passkeyChallenges --enable-ttl --project <PROJECT_ID>
```

It is only housekeeping. Expiry is enforced by comparing against `expiresAt` in the
function, never by the document having disappeared — TTL deletion can lag by up to 24 hours
and is not a security boundary.

**Not `corbado_auth_firebase`.** [corbado/flutter-passkeys](https://github.com/corbado/flutter-passkeys)
is a useful reference for the flow above — it is the same shape, function verifies then
mints a custom token — but its Firebase package is not the route here, for four independent
reasons: its README states the package is currently broken with no ETA; its support table
marks **Web as untested**, and Web is where this project is developed and demonstrated; it
still needs
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

## Importing a menu from a photo

Typing forty dishes into a phone is the moment a new store gives up on the app, and it is
the moment it is least invested in seeing it through. So registration offers a photograph
first — Step 3 of [the two paths](#the-two-paths) — and Store Settings &rarr; Edit Menu
keeps the same entry point behind the 🖹 button for the second page of the menu, or the
one that changed last week.

### Why a vision model rather than OCR

The hard part is not reading the characters. It is that a menu is a **layout**: two
columns, prices right-aligned, a decorative heading every ten dishes, and half a page of
whitespace between 牛肉麵 and the 120 that belongs to it. A text recogniser hands back lines
and bounding boxes and leaves the pairing to the caller — and the pairing is the whole job,
different for every shop, breaking on the first two-column card or 大130/小100 double price.

| Route | Verdict |
| --- | --- |
| On-device OCR (ML Kit) | Free and offline, but it returns text lines, not dishes. The name↔price pairing, section headings, and double prices are all left as heuristics to write and maintain. There is no way to ask for `zh-Hant` specifically either — one Chinese script model covers both, and Taiwanese menus love brush and display faces |
| Cloud OCR (Vision API) | Costs money and still leaves the pairing to the caller. Strictly worse than the row above for this |
| **Vision model** | Does the pairing itself, because it is reading for meaning rather than for glyphs. One call returns dishes, prices, portions and section headings together |

Kept in mind, not discarded: on-device OCR is the right route the day this has to work with
no signal. It is not the right route for the first version.

### What is asked of the model, and what is not

The split is deliberate. Ask the model for what only a reader can know; do everything a
rule can do in code, where it is testable.

| The model | The app |
| --- | --- |
| Reading the characters | Matching a section heading to an existing `categoryId`, or creating one |
| Pairing a dish with its price | De-duplicating against dishes already on the menu |
| Which section a dish sits under | Checking the price arithmetic |
| Flagging rows it is unsure of | Generating ids, assigning `sortOrder`, picking icons |

Two schema decisions carry weight:

**`name` and `variant` are separate fields, joined once, in the app.** Asked for a single
field the model returns `牛肉麵 大` one time and `牛肉麵(大)` the next, and two dishes
differing only by a separator are two dishes forever. A dish sold at two prices arrives as
two entries sharing a `name` — which is exactly what lets
[menu engineering](lib/analysis/menu_engineering.dart) say later which size actually sells.

**Icons are never asked for.** `MenuItem.icon` is a MaterialIcons code point; a model
guessing at code points produces dishes with an icon nobody chose and no way to tell which
were guesses. Every imported dish starts on `Icons.restaurant`.

### Taking the photograph

The app opens the camera itself. It does not fire `ACTION_IMAGE_CAPTURE` and let
another app take the picture, which is what `image_picker`'s camera source does.

That route works on most phones and cannot be relied on for any of them. Whether an app
answers the capture intent is not a property of Android — it is a property of whatever the
manufacturer, the carrier and the owner left installed and enabled, and a shop's phone is
exactly the phone nobody curated. Sony ships the case that proves it: on an Xperia the
stock camera is disabled and its replacements register only `STILL_IMAGE_CAMERA`, which
opens a camera and never hands a file back, so the intent resolves to nothing:

```
$ adb shell cmd package query-activities -a android.media.action.IMAGE_CAPTURE
No activities found
```

The phone reports `no_available_camera` while holding three cameras. Package visibility
(`<queries>`) does not help — it lets an app *see* a camera app, and there is none to see.
The same hole opens on any device whose camera app was replaced, disabled, or restricted
by a work profile, so the fix is not to special-case a brand but to stop depending on
other apps: [menu_capture_page.dart](lib/settings/menu_capture_page.dart) drives the
sensor. On Android that is `camera_android_camerax` — CameraX, Google's own
device-compatibility layer, written for this exact problem.

Three consequences worth knowing:

* **The app declares `android.permission.CAMERA`** — an opened sensor needs it, a borrowed
  one does not. `<uses-feature android:required="false" />` keeps a camera-less tablet able
  to install, because *Choose image* still works there.
* **Resolution is requested, not guaranteed.** The controller tries 1080p, then 720p, then
  480p. `max` is never asked for: a dense menu wants resolution, but a 12MP frame is
  megabytes of upload and the recogniser works at a 1568px edge anyway. Failing outright on
  a handset that cannot do 1080p would mean the app works on the developer's phone and not
  on the shop's.
* **Web keeps `image_picker`.** In a browser there is no sensor to open, only
  `getUserMedia` behind a permission prompt and an HTTPS origin; the file input is what
  browsers are good at, and on a phone browser it offers the camera anyway.

### Which API, and how that was established

`POST /v1beta/models/{model}:generateContent`, taken from the service's own **discovery
document** rather than from a documentation page:

```sh
curl 'https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta'
```

This is worth spelling out because the documentation and the service disagree. The docs
describe an "Interactions API" at `/v1beta2/interactions` and recommend it for new work.
No such resource exists in the discovery document for `v1`, `v1beta`, `v1beta2` or
`v1alpha`, and posting to it returns 404. `v1beta2` is real but is the PaLM-era version —
`generateText`, `generateMessage` — not the Interactions API. When the two disagree, the
discovery document is the one generated from the running service.

The same source settles the request shape, and it is not what a prose page suggests:

| | Documentation page said | Discovery document says |
| --- | --- | --- |
| Schema types | `"type": "object"` | `"type": "OBJECT"` — an enum of `STRING`/`NUMBER`/`INTEGER`/`BOOLEAN`/`ARRAY`/`OBJECT`/`NULL` |
| Optional fields | `"type": ["string", "null"]` | A separate `"nullable": true` |
| Payload | `input: [...]`, `response_format` | `contents: [{ role, parts }]`, `generationConfig.responseSchema` |
| Images | `{ type: "image", data }` | `{ inlineData: { mimeType, data } }` |
| Reading the answer | `output_text` | `candidates[0].content.parts[]` |

Two of those would fail silently rather than loudly. Parts carry a `thought` flag and the
model's reasoning arrives in the same array, so joining every part concatenates reasoning
into the JSON and turns a good response into a parse error; and a `finishReason` of
`MAX_TOKENS` yields a half-written object that fails three lines later with a far less
useful message. Both are handled explicitly.

**Model fallback is not belt-and-braces.** `gemini-3.7-flash` returned 503 UNAVAILABLE four
times in a row during testing. Retrying one model is not a plan when that model is the
thing failing, so the call falls through three of them. `gemini-2.5-flash` is deliberately
not among them — it answers 404 with "no longer available to new users".

### Nothing is written until somebody says yes

The function recognises and returns. It writes nothing — the draft goes back to the app, a
person corrects it on screen, and the write happens client-side under the rules that
already govern `menuItems`. Writing server-side would mean a store that wanted to undo an
import had to delete dishes one at a time, and menu items are *retired* rather than
deleted, so "undo" would leave a drawer of inactive dishes nobody can explain.

That review screen is where the feature is won or lost. A menu is forty to eighty dishes,
and asking somebody to read eighty rows on a phone is asking them to stop reading at about
row twelve — at which point "saves typing" has been traded for "saves typing and is
sometimes silently wrong", which is worse than not having it. So rows are shown in two
groups, and only the flagged ones are expanded.

A row is flagged for five reasons, and the split between them is the point:

| Flag | Source |
| --- | --- |
| Unclear in the photo | The model's own doubt — blur, glare, a corner cut off |
| No price read | The app |
| Unusual price | The app — not a multiple of five, which Taiwanese menus almost always are |
| Price out of line with the section | The app — more than 3× either side of that section's median |
| Appears twice | The app |

Four of the five are the app's, because **the model's hedge misses the case that matters
most**: a price read *confidently* and wrongly. 120 transcribed as 720 raises no doubt in
the reader and would sail straight through. The outlier check is the one that catches it.

The 3× band is deliberately wide, and the median needs a section of at least four dishes
before it is trusted. A section really can hold a 60 dollar side next to a 180 dollar main,
and a rule that cried wolf would train people to approve without looking — which is the one
outcome that makes this worse than typing it in. The rules are in
[menu_import_repository.dart](lib/database/menu_import_repository.dart) and tested against
the shapes a misread digit actually makes in
[test/database/menu_import_test.dart](test/database/menu_import_test.dart).

Flags recompute across the whole draft on every edit, not per row: two of the checks are
about a row's neighbours, so correcting one price can clear an outlier flag on a different
one, and renaming a dish can create or resolve a duplicate.

### Writing

Categories live inline on the store document while dishes live in a subcollection, so a
dish written before its category exists points at a `categoryId` nothing resolves. Both go
in the same `WriteBatch`, which is what stops that happening halfway. Category names match
case-folded, so an import does not create a second "Drinks" beside the existing "drinks",
and only headings that dishes actually ended up under get created.

Imported dishes land *after* whatever is already on the menu. Nothing is reordered by an
import — a shop that has arranged its menu should not find it rearranged because somebody
photographed a second page.

No audit entry is written. The log covers the four actions that can move money without a
sale happening — voiding, editing, discounting, repricing — and adding dishes is none of
them, any more than typing them in by hand is.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- TROUBLESHOOTING -->
## Troubleshooting

<details>
<summary>The web build shows the spinner, then a blank screen — <code>Cannot read properties of undefined (reading 'init')</code></summary>

The Passkeys web SDK is missing. Either [web/passkeys/bundle.js](web/passkeys/bundle.js) is
not there, or the `<script src="passkeys/bundle.js">` tag ahead of the Flutter bootstrap in
[web/index.html](web/index.html) was dropped.

This is not a passkey bug — it kills the entire app before `main()` runs, so every screen is
blank for every user. The full explanation is in
[The Passkeys web SDK is not optional](#the-passkeys-web-sdk-is-not-optional).

Confirm it in the browser console before assuming anything else: the giveaway is
`TypeError: Cannot read properties of undefined (reading 'init')`, thrown twice, with a
`registerPlugins` frame in the stack. Nothing on the page will say so — a Dart exception at
plugin-registration time leaves no error text behind, only the background colour.
</details>

<details>
<summary><code>PlatformException(no_available_camera, No cameras available for taking pictures.)</code></summary>

Almost never true. Since Android 11 the system hides every app this one has not declared an
interest in, so resolving the capture intent returns null and `image_picker` reports it as
a missing camera — on a phone that plainly has two. The fix is the `<queries>` block in
[android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml):

```xml
<queries>
    <intent>
        <action android:name="android.media.action.IMAGE_CAPTURE" />
    </intent>
</queries>
```

It is declared as an intent rather than a package name so it matches whichever camera app
the phone ships with. No `CAMERA` permission is needed — the photo is taken by that other
app, and declaring the permission would only oblige this one to ask for it at runtime.

On a device that really has no camera, *Choose image* still works.
</details>

<details>
<summary><code>The menu reader is not deployed</code> / <code>The passkey service is not deployed</code></summary>

Not a bug — the callables genuinely are not there. Check with:

```sh
firebase functions:list --project <PROJECT_ID>
```

"No functions found" means [step 4](#4-deploy-the-cloud-functions-optional) has not been
run against this project, or was run against a different one. Both features report this
independently, so seeing it from only one of them means something narrower: either the
`GEMINI_API_KEY` secret was never set (menu import fails, passkeys work), or the region in
the Dart client and `functions/src/config.ts` have drifted apart — a callable is addressed
by region *and* name, and a mismatch reads as "not found" rather than as a wrong region.
</details>

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
* [x] Import a menu from a photo — see [Importing a menu from a photo](#importing-a-menu-from-a-photo)
* [ ] Apple sign-in (blocked on iOS configuration)

**Phase 5 — shipping** ✅

* [x] Offline order queue; orders survive a dropped connection and drain on return
* [x] Payment methods and delivery-platform commission, both reflected in the reports
* [x] Import orders from a delivery platform's statement
* [x] Role-aware settings — manager-only rows are read-only rather than failing on save
* [x] An in-app manual explaining where every figure comes from
* [x] Google Play in-app updates
* [x] A daily ceiling on menu-import spend (`functions/src/quota.ts`)
* [x] App Check wired into startup — see [§5](#5-app-check)
* [x] AGPL-3.0, a security policy and contribution guidelines

**Not tied to a phase**

* [x] Dark mode apply
* [ ] Language change / international language support
* [ ] Material You theme apply
* [ ] Notification to "add transaction" at a set time
* [ ] iOS configuration

See the [open issues](https://github.com/ADSFAaron/Revenue/issues) for a full list of proposed features (and known issues).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### What it is allowed to cost

This is the only call in the project with a per-invocation price. One import can
reach the model up to six times — three models, two attempts each — carrying up
to four photographs. Everything else here (a Firestore write, a function
invocation) needs millions of repetitions before it is worth a coffee.

`requireMenuEditor` in [menu_import.ts](functions/src/menu_import.ts) already
refuses anyone who is not an owner or manager of the store, and that check is
worth having — but it is **not a perimeter**. Registration makes you the owner
of a brand-new store, and there is no email verification, so a stranger is an
owner about four seconds after deciding to be one. The role check protects a
shop from its own staff. It does not protect the project from the internet.

[quota.ts](functions/src/quota.ts) is what does. Two counters, both checked and
incremented in one transaction before any model is reached:

| Counter | Document | Default |
| --- | --- | --- |
| Per store | `stores/{storeId}/usage/menuImport` | 5 a day |
| Per project | `usage/menuImport` | 200 a day |

Both are needed. A per-store limit multiplied by the number of stores is not a
limit, because stores are free to create; the project counter is the one that
actually decides the worst case on a month's bill. It logs a warning past 80%,
while there is still a day to react in.

Neither is refunded on failure — a failed import has usually been through
several model attempts by then, and refunding would make failure the cheapest
way to spend the budget. The day rolls over by comparing a stored `day` field
rather than by a scheduled cleanup, so there is no cron job to deploy, pay for,
or discover has been silently failing for a month.

Both documents sit outside anything a client may touch: `firestore.rules` ends
in a deny-all and no rule matches those paths, so the only writer is the
function, running as admin.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->
## Contributing

Contributions are welcome. **[CONTRIBUTING.md](CONTRIBUTING.md) is the one to
read first** — it covers the ground rules this codebase actually enforces (no
widget touches Firebase; the security rules *are* the security model; an
unknown number is shown as unknown) and, importantly, what the AGPL means for
your pull request.

For anything larger than a fix, open an issue before writing code. Most design
questions here are decided by constraints that are not visible from outside.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

Everything has to pass `flutter analyze` and `flutter test`, and
`flutter build apk --debug` too if you touched a plugin or anything under
`android/`.

### Found a security hole?

Do not open an issue. See **[SECURITY.md](SECURITY.md)** — report it privately
through the repository's Security tab. That document also lists the things that
look like vulnerabilities here and are not, so you can check before spending
time on one.

### What changed between versions

See **[CHANGELOG.md](CHANGELOG.md)**.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Top contributors

<a href="https://github.com/ADSFAaron/Revenue/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=ADSFAaron/Revenue" alt="contrib.rocks image" />
</a>

<!-- LICENSE -->
## License

Distributed under the **GNU Affero General Public License v3.0**. The full text
is in [`LICENSE`](LICENSE).

In plain terms:

* You may read, run, modify and redistribute this code, and you may run it for
  your own shop, commercially, without owing anybody anything.
* If you modify it and let other people use your modified version **over a
  network** — a hosted till, a SaaS build of this app — you must publish your
  modified source under the same licence. That network clause is what the AGPL
  adds over the ordinary GPL, and it is the reason this project uses it.
* The copyright stays with the project's authors, so the authors remain free to
  offer the same code under a separate commercial licence to anyone who would
  rather not be bound by the AGPL.

The app links to this repository from **Account & app › Source code**, which is
how somebody using the software over a network gets to its source.

> **Note on the previous wording.** This section used to read "Distributed under
> the MIT License. See `LICENSE.txt`" — boilerplate left over from the README
> template. No `LICENSE.txt` was ever committed, so until now the repository was
> public with no licence at all, which under default copyright means all rights
> reserved. The AGPL-3.0 above is the licence that applies.

### Contributing under this licence

Contributions come in under the AGPL-3.0 on the same terms as the rest of the
project (inbound = outbound). There is no contributor licence agreement today;
one would be needed before any commercial relicensing that included outside
contributions.

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
