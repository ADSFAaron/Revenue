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

## Short description (max 80 · actual 76)

```
A till for small food shops. Works offline, and shows what each dish earns.
```

Alternative:

```
Take orders offline, photograph your menu in, and see real profit per dish.
```

---

## Full description (max 4000 · actual 3702)

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

## Required links

| Field | Value |
| --- | --- |
| Privacy policy | `https://revenueapp-b8849.web.app/privacy.html` |
| Contact email | `aaron-chuang@haoder.dev` |

---

## Checklist

| Item | Spec | State |
| --- | --- | --- |
| Short description | ≤ 80 chars | ✅ 76 |
| Full description | ≤ 4000 chars | ✅ 3702 |
| App icon | 512×512 32-bit PNG with alpha | `play/app-icon-512.png`, from `assets/icon/AppLogoIcon.png` |
| Feature graphic | 1024×500 PNG/JPEG, **no** alpha | `play/feature-graphic.png` |
| Phone screenshots | 2–8, each side 320–3840px, long edge ≤ short × 2 | ✅ 6 in `play/screenshots/`, 1440×2560, ratio 1.78 |
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
