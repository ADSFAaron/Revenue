# Google Play store listing — English (United States)

Language code `en-US`, and for now the only one.

The app's interface is English throughout — there is no `flutter_localizations`,
no `supportedLocales` and no `.arb` files in the project. A store listing in
Traditional Chinese was written first and is what this text was translated back
from, but publishing it would have put a Chinese listing in front of people who
then open an English app. That is the mismatch reviewers notice and the one
users leave a one-star review about, so the listing follows the app rather than
the market until the app can follow the market.

The Chinese copy is kept, unused, at `play/listing-zh-TW.md`. When Revenue is
localised it goes back into service largely as it stands.

Limits: short description 80 characters, full description 4000.

---

## App name (max 30)

```
Revenue — Shop Till & Profit
```

---

## Short description (max 80 · actual 75)

```
A till for small food shops. Works offline, and shows what each dish earns.
```

Alternative:

```
Take orders offline, photograph your menu in, and see real profit per dish.
```

---

## Full description (max 4000 · actual 2617)

The version to paste. Plain sentences, one idea each, headings you can skim —
the store page is read on a phone by somebody deciding in ten seconds.

```
Revenue is a till for small food shops. It takes the orders, and it works out what you actually earned.

Put the ingredient cost against each dish, and Revenue shows the profit on every order, every day and every dish — not just the takings.


■ Works when the Wi-Fi doesn't

Kitchen Wi-Fi drops. Orders rung up while offline are held on the phone and sent as soon as the connection is back, with a bar showing how many are still waiting. When figures are not live, the screen says so instead of showing stale numbers as current.


■ Photograph the menu instead of typing it

Nobody wants to type in forty dishes. Take a photo of your menu and Revenue reads it into dishes and prices. Nothing is saved until you confirm it. Photograph a second page, or a few changed dishes, any time.


■ See which dishes actually earn

- Menu quadrants: every dish sorted into Stars, Workhorses, Puzzles and Duds, by how well it sells and how well it earns. A bestseller list cannot show you the dish that sells most while thinning the profit on every plate.
- Ingredient cost ratio: food cost as a share of takings, with an alert when you cross your limit.
- Busy periods: by day of the week and by hour, kept separate — Tuesday evening and Saturday evening are two different businesses.
- Ordered together: which dishes your customers buy in the same order.


■ Delivery platforms, commission included

Import a delivery platform's statement and set its commission rate. Without that rate a delivery order books as pure revenue and your margin is wrong by whatever the platform took.


■ Built for everyone in the shop

- Three roles: owner, manager and staff. Staff take orders and check what they rang up, but cannot change prices or settings.
- Settings staff cannot change are shown read-only, not hidden, so hand-over reconciles.
- An order just rung up wrong can be fixed by whoever rang it, for five minutes. After that it takes a manager.
- Every void, edit and price change is logged: who, what, when.


■ Also

- Set the hour your trading day rolls over.
- Define your own payment methods; reports split the takings by them.
- Tax inclusive or added on top.
- Export reports to Excel.
- Sign in with a fingerprint, face or screen lock (passkeys).
- Dark mode, and text that scales.
- A full manual inside the app, explaining where every figure comes from.


■ Open source

Revenue's source is public under the AGPL-3.0 licence. You can read it, change it, and run your own copy.

Source: https://github.com/ADSFAaron/Revenue


An internet connection is needed to create an account. Day-to-day order taking works offline.
```

---

## Full description — longer alternative (3697)

The original, fuller copy. Same substance, more prose. Use it if the plain
version reads as too bare beside comparable listings.


```
Revenue is a till for small food shops, and a ledger that does the arithmetic for you.

Most till apps tell you how much you sold. Revenue is built to answer the question after that one — whether selling it that way actually made you anything. Fill in the ingredient cost of each dish and it works out what every order, every day and every dish really leaves behind.


■ Keeps trading when the connection does not

Unreliable kitchen Wi-Fi is the normal case, not the exception. When the connection drops, the screen says plainly that you are looking at the last figures this device received, rather than letting stale numbers pass as live ones. Orders rung up meanwhile are held on the phone and sent automatically when the connection returns, with a bar showing how many are still waiting.


■ Photograph the menu instead of typing it

The moment people give up on a till app is being asked to type in forty dishes one at a time. Revenue reads a photograph of your menu into dishes and prices, and nothing is saved until you have confirmed it. A second page, or the few dishes you changed last week, can be photographed again any time.


■ Analysis you can act on, not a wall of charts

- Menu quadrants: every dish sorted by how well it sells and how well it earns — Stars, Workhorses, Puzzles and Duds. A bestseller list cannot show you the dish that sells most while thinning the profit on every plate. This can.
- Ingredient cost ratio: what food costs as a share of takings, with a line you get told about when you cross it.
- Busy periods: day of the week and hour of the day, kept separate. Tuesday evening and Saturday evening are two different businesses, and averaging them hides both. It also tells you how many of that weekday the average came from — one Saturday is a coincidence, not a pattern.
- Ordered together: pairs like "six in ten customers who order beef noodles add a marinated egg", found in your actual orders.


■ Delivery platforms, commission included

Delivery orders sit in the platform's own back office, and a day that sold well there reads as a quiet day in your books until you bring them in. Revenue imports a platform's statement and lets you set each platform's commission rate — without that figure a delivery order books as pure revenue and your margin is wrong by whatever the platform took.


■ Built for everyone in the shop

- Three roles: owner, manager and staff. Staff can take orders and check what they just rang up, but cannot change prices or settings.
- Settings you cannot change are shown read-only rather than hidden. At hand-over you need to see the tax rate and the trading-day cutoff to reconcile against them.
- An order you just got wrong can be fixed by whoever rang it up, for five minutes. After that it takes a manager. Both leave a record.
- Every void, edit and price change goes into a change log: who, what, when.


■ And

- Set the hour your trading day rolls over. An order at two in the morning belongs to the previous day if you say it does.
- Define your own payment methods; reports break the takings down by them, so counting the cash drawer reconciles.
- Tax can be inclusive or added on top.
- Export reports to Excel.
- Sign in with a fingerprint, face or screen lock (passkeys).
- Dark mode, and text that scales.
- A full manual inside the app explaining where every figure comes from.


■ Open source

Revenue's source is public, under the AGPL-3.0 licence. You can read it, change it, and run your own copy. A shop's ledger ought to be something you can see the inside of.

Source: https://github.com/ADSFAaron/Revenue


An internet connection is needed to create an account. Day-to-day order taking works offline.
```

---

## Release notes — "What's new" (max 500 · actual 466)

Play Console asks for this per language, under the release. It is the first
upload, so it has to introduce the app as well as announce it — and the panel on
the store page collapses after three or four lines, so the first sentence is
doing most of the work.

```
First release.

Most till apps tell you how much you sold. Revenue answers the question after that one — whether selling it that way made you anything.

- Works offline: orders wait on the phone and send themselves
- Photograph your menu instead of typing in forty dishes
- See which dishes sell well but earn thinly
- Delivery commission counted, so margins are real
- Owner, manager and staff roles; every change recorded
- Excel export, passkey sign-in, dark mode
```

For later releases this becomes an ordinary changelog — what changed, in the
words of somebody who uses the app rather than writes it. CHANGELOG.md is the
developer-facing version and is not a substitute: "R8 is on for release builds"
means nothing to a shopkeeper.

---

## Required links

| Field | Value |
| --- | --- |
| Privacy policy | `https://revenueapp-b8849.web.app/privacy.html` |
| Contact email | `aaron-chuang@haoder.dev` |

---

## Checklist

| Item | Spec | State |
| --- | --- | --- |
| Short description | ≤ 80 chars | ✅ 75 |
| Full description | ≤ 4000 chars | ✅ 2617 |
| App icon | 512×512 32-bit PNG with alpha | `play/app-icon-512.png`, from `assets/icon/AppLogoIcon.png` |
| Feature graphic | 1024×500 PNG/JPEG, **no** alpha | `play/feature-graphic.png` |
| Phone screenshots | 2–8, each side 320–3840px, long edge ≤ short × 2 | ✅ 6 in `play/screenshots/`, 1440×2560, ratio 1.78 |
| 7-inch tablet screenshots | same rules, separate slot | ✅ 6 in `play/screenshots-tablet7/`, 1920×1200, ratio 1.60 |
| 10-inch tablet screenshots | same rules, separate slot | ✅ 6 in `play/screenshots-tablet10/`, 2560×1600, ratio 1.60 |
| Privacy policy URL | Required for every app | `web/privacy.html`, live after `firebase deploy --only hosting` |

> ⚠️ This phone is 1096×2560 (1:2.34), which is **past Play's 2:1 limit — raw
> screenshots off it are rejected**. Composite them onto a 1440×2560 (9:16)
> ground with a caption and margins, which also makes the listing page look
> like somebody meant it.

### The screenshots

Raw device captures are kept in `play/captures/`, framed output in
`play/screenshots/`. Re-frame after any caption change with:

```sh
python3 tool/play_screenshots.py play/captures play/screenshots
```

Captions live in `PANELS_EN` in that script, and a capture is paired to its
caption by the number its filename starts with — so a single panel can be
re-shot without disturbing the others.

| # | Screen | Caption |
| --- | --- | --- |
| 01 | Today — stat cards and last transactions | Today, at a glance |
| 02 | Insights → Summary | Which dishes actually earn |
| 03 | Add Order, offline, with an order queued | Keeps trading when the Wi-Fi doesn't |
| 04 | Import menu | Photograph the menu instead of typing it |
| 05 | Reports → Month | Takings you can read |
| 06 | Store Settings | The rules your shop actually runs on |

### The tablet sets

Play keeps a separate slot per form factor, and filling the tablet ones with the
portrait phone panels is what "not designed for tablets" looks like on a store
page. So the tablet panels are landscape — headline in a column beside the
device rather than above it — which is `frame_landscape` in the same script:

```sh
python3 tool/play_screenshots.py play/captures-tablet7  play/screenshots-tablet7  tablet7
python3 tool/play_screenshots.py play/captures-tablet10 play/screenshots-tablet10 tablet10
```

**One emulator, two geometries.** Android Studio's `Medium_Tablet` and
`Pixel_Tablet` are the same device on paper — both 2560×1600 at 320dpi — so
switching AVDs does not get you a 7-inch layout, it gets you the same picture
twice. What separates the two slots is the `sw` bucket the app lays out
against, and that is set with `wm`:

| Slot | Emulator | dp | Bucket |
| --- | --- | --- | --- |
| 10-inch | native 2560×1600 @ 320dpi | 1280×800 | `sw800dp` |
| 7-inch | `wm size 1920x1200` + `wm density 320` | 960×600 | `sw600dp` |

Both are past `constraints.maxWidth >= 600` in [lib/home.dart](../lib/home.dart),
so both draw the `NavigationRail` rather than the phone's bottom bar — which is
the point of shipping tablet screenshots at all. Reset afterwards with
`adb shell wm size reset && adb shell wm density reset`.

**The emulator wins on panel 03.** On the phone this one had to be shot by hand,
because turning the network off to raise the offline banner also kills wireless
adb, so the tooling goes down with the network it caused. An emulator's adb runs
over its own control socket, so `adb shell cmd connectivity airplane-mode enable`
raises the banner with the driving still connected — the offline strip, the
queue bar and the "Saved on this device" toast all land in one automated frame.

**Rebuild before capturing.** The `app-release.apk` sitting in `build/` was from
before the offline queue landed, and its banner still read "Orders cannot be
rung up until the connection is back" — the opposite of what the listing
promises. A screenshot is only worth as much as the build under it: run
`flutter build apk --release` first and check the APK is newer than `HEAD`.
Note that a build made since `android/key.properties` exists is signed with the
upload key, so it will not install over a debug-signed one — uninstall first.

**03 had to be taken by hand**, and is the better for it. The offline banner
only appears once Firestore has actually lost its connection, which means
turning off both Wi-Fi and mobile data — and the phone is driven over wireless
adb, which Android switches off along with the Wi-Fi. So the tooling goes down
with the network and cannot photograph what it caused. Taken on the device in
airplane mode instead, with an order rung up first, it shows the whole feature
in one frame: the offline strip, the queue bar counting what is waiting, and
the confirmation that the order was saved. `play/captures/unused/` holds the
first attempt — the Today screen, which is honest but reads as an empty app,
because 1 September is a fresh trading day with no seeded orders in it yet.

**Panel 01 is the weak one.** The trading day runs to 05:00, so a capture taken
after midnight shows a day that is still open — NT$2,630 against a 55-order
target. Nothing is wrong with it, but it undersells. Re-shoot it during trading
hours, or after ringing a few orders up, and drop the new file in as
`play/captures/01-home.png`.
