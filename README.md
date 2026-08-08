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
        <li><a href="#3-run-the-app">3. Run the app</a></li>
      </ul>
    </li>
    <li><a href="#building-a-release-build">Building a release build</a></li>
    <li><a href="#platform-support-status">Platform support status</a></li>
    <li><a href="#project-structure">Project structure</a></li>
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

Revenue is a Flutter app for recording and analysing a small store's sales. It covers
day-to-day order entry, a transaction history, and a statistics page with charts, gauges
and Excel export. All data lives in Firebase (Cloud Firestore + Realtime Database), with
Firebase Authentication for sign-in and Firebase Storage for uploaded files.

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

### 3. Run the app

```sh
flutter devices          # confirm your target is listed
flutter run
```

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
| Android | Fully working — the primary target |
| Web | Firebase configured; UI is not verified |
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
│   ├── overview.dart         # Landing page: totals and quick stats
│   ├── transaction.dart      # Order history
│   ├── statistics.dart       # Charts, gauges, date-range picker, Excel export
│   ├── store.dart
│   └── addorder.dart
├── settings/                 # App, user, store and staff settings
├── database/firestore.dart   # Firestore access layer
└── animation/                # Shared page transitions

android/app/src/main/kotlin/com/adsf/revenue/MainActivity.kt
                              # Must match the `namespace` in android/app/build.gradle
```

> The package name is `com.adsf.revenue`. If you ever rename it, `MainActivity.kt` has to
> move to the matching directory *and* have its `package` line updated — otherwise the app
> installs fine and then crashes on launch with `ClassNotFoundException`.

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

* [ ] Overview Page connect with DB
* [ ] Transaction Page connect with DB
* [ ] Statistics Page
  * [ ] Connect with DB
  * [x] Chart integrate with data
  * [x] Change day/week/month/year time selection
  * [ ] Swipe page to change view date
  * [ ] Export Excel for all revenue
* [ ] Settings Page
  * [x] Edit menu add icon dynamic choose
  * [ ] Store page editing with manager
  * [ ] Dark mode apply
  * [ ] Language change
  * [ ] Notification to "add transaction" with specific time
* [ ] Material You theme apply
* [ ] International language support

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
