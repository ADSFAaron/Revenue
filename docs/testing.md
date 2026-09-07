# What is tested, where, and what is not

Four suites. Three of them run in CI on every push and pull request
([.github/workflows/ci.yml](../.github/workflows/ci.yml)); the fourth is a
person with a tablet, and this document exists mostly to keep that fourth list
short and honest.

| Suite | Command | Runs on | What only it can prove |
| --- | --- | --- | --- |
| Dart | `flutter test` | every push | The app's own logic, and the journeys through it |
| Firestore rules | `npm run emulate` in `test/rules/` | every push | That the server refuses what it should |
| Cloud Functions | `npm test` in `functions/` | every push | The model-facing code the app cannot reach |
| By hand | — | before a release | Anything with a camera, a fingerprint or Google's servers in it |

A fifth thing runs on pull requests and proves nothing about the app: **mutation
analysis**, which asks whether the four suites above would notice if the change
were wrong. See the last section.

---

## 1. Dart — `flutter test`

Three kinds of test live under `test/`, and the difference between them is
worth keeping straight.

**Unit tests** (`test/models/`, `test/analysis/`, `test/export/`,
`test/database/`) take a pure function or a plain object and check its
arithmetic. Fast, exact, and blind to anything that happens between two
objects.

**Widget tests** (`test/widgets/`, `test/settings/`) mount one widget with its
data handed in, and check what is on screen: contrast and tap targets against
Flutter's own accessibility guidelines, behaviour at 2x text scale, what
survives a Cancel, what a lock covers.

**Journey tests** (`test/journey/`) are the newest, and cover the part neither
of the others can see: the joins. An order that writes without error and then
is not in the history is not a bug in `submit` — `submit` is fine. It is a bug
in the seam between two collections, and only something that goes through both
can find it.

[test/journey/shop.dart](../test/journey/shop.dart) builds a whole shop in
memory — a fake Firestore, a fake FirebaseAuth, and the app's **real**
repositories wired to both — and each test drives it the way a counter does.
No emulator, no device, no network, so it runs on every `flutter test` rather
than on the days somebody remembers to start something.

What the journeys cover:

| File | The journey |
| --- | --- |
| `registration_test.dart` | Opening a new store; joining one with an invite code, at the invited role; a spent, expired or invented code |
| `sign_in_test.dart` | Signing back in; a wrong password reaching the screen as a *wrong password*; two accounts on one tablet staying separate |
| `home_test.dart` | An untraded shop reading **zero** rather than blank; every figure moving after one sale; yesterday staying still |
| `menu_test.dart` | Adding, renaming, repricing and retiring a dish; a repricing leaving an audit entry; a new price never rewriting what was already sold |
| `order_test.dart` | Ringing up, and finding it in the history with the right number, total and attribution |
| `correction_window_test.dart` | The five-minute rule per role; viewing never being gated; an allowed edit leaving the day's takings correct; voiding |
| `analytics_test.dart` | The rollup agreeing with the orders, broken down by dish, hour, channel and payment; ranges of days; the Insights matrix, busy-times profile and headlines built from real trading |
| `screens_test.dart` | The till, staff, order detail, add-order and Insights screens, mounted for real — see below |
| `reports_test.dart` | Reports; the store overview and its lifetime aggregate; the Busy times, Prep and Pairings tabs |
| `settings_test.dart` | The menu editor, order history, change history, categories, payment methods and store settings |
| `driving_test.dart` | **Using** those screens — filling forms in, pressing Save, and reading the result back out of Firestore |
| `arranging_test.dart` | The big-button till, and dragging the menu, categories and payment methods into a new order |
| `offline_test.dart` | Orders rung up with no connection: queued, persisted, drained, and safe to send twice |
| `slip_test.dart` | The paper-slip reader — the request it sends, the progress it narrates, and every way it can refuse |

### Screens, not just data

Every journey above stops at the data: the takings *are* zero, the order *is*
in the collection. `screens_test.dart` takes the last step and mounts the
actual widget, because a screen can read the right document and put it in the
wrong place, spin forever because a stream was never listened to, or show a
zero when what it got was an error. The last of those shipped — the comment in
`transaction.dart` about the em dash is what it left behind.

What it covers: the till screen reading zero rather than a spinner and moving
after a sale, with the order in the list and not only in the totals; the staff
screen showing everybody including somebody removed, and offering the controls
to an owner or manager but never on their own row and never on the owner's; the
order detail screen greying out **Edit** and **Void** for staff once the
correction window has passed while an owner keeps both; the till offering the
shop's own menu and never a retired dish; Reports adding a period up and paging
back to an empty one; the store overview's lifetime aggregate; the menu editor
hiding retired dishes until asked and giving staff the menu to read rather than
to edit; the order history keeping a voided order and marking it; the change
history naming who repriced what; and all five Insights tabs, including
Pairings refusing to run until it is asked and then finding the pairing.

`driving_test.dart` goes the other way round from all of the above. The rest
prove a screen shows what the data says; that one proves that filling a form in
and pressing Save reaches Firestore, and reaches it with what was typed. It
checks the result with a one-shot `get` rather than by looking at the screen it
just used — a screen that draws the dish it thinks it saved is not evidence
that anything was saved. It covers adding, repricing and retiring a dish;
ringing an order up through the steppers and pressing Add order; voiding with
its confirmation, and Cancel on that confirmation changing nothing; promoting,
removing and restoring a colleague; adding, renaming and deleting a category,
and being refused when dishes are still in it; adding a payment method; issuing
an invite code and then actually spending it; and renaming the shop, setting a
tax rate, targets and the trading-day cutoff.

**Two real bugs came out of writing these**, both in `statistics.dart` and both
invisible on a network round trip:

* `_reportStream` is a broadcast stream that `_setPeriod` subscribes to before
  the widget does. A broadcast stream does not replay, so if the first report
  arrived before the first build — which a cached read can manage and a network
  read cannot — the `StreamBuilder` waited for a second report that, on a shop
  not currently trading, never comes. The page spun for as long as it was open.
  Fixed with `initialData: _latestReport`, which the page was already keeping
  for the export button.
* `StreamBuilder` keeps its last snapshot when the stream it is given changes.
  Paging to the previous period therefore redrew the heading as "Yesterday"
  over **today's** figures and left them there. Fixed with a `ValueKey(period)`
  so the builder starts clean. A figure under the wrong date is the worst thing
  that page can show: it reads as a fact about a day the shop cannot check any
  other way.

This is possible because the repositories in
[lib/database/repositories.dart](../lib/database/repositories.dart) can be
replaced. `useRepositories` there is the only supported way in, and
`shop.install()` is what calls it. They are lazily-built getters over nullable
fields rather than plain variables, and that detail matters: several of these
constructors call `FirebaseFunctions.instanceFor`, which throws without an
initialised Firebase app, so merely *reading* one of the names in a test would
build something that cannot exist there.

### Two things the fake gets wrong, and how they are handled

Both are documented in `shop.dart` at the point they are worked around.

* **`fake_cloud_firestore` throws away `SetOptions` inside a transaction.**
  Its transaction stand-in calls `documentReference.set(data)` with the options
  dropped, so every `tx.set(..., SetOptions(merge: true))` lands as a
  whole-document replace. The daily rollup is written exactly that way, as a
  merge of `FieldValue.increment`s — so under the plain fake a shop's second
  order of the day *replaces* the first and the takings read as whatever the
  last order was. Tests written against that would have been asserting a fake's
  bug. `_Firestore` in the harness puts back the two things Firestore actually
  promises: writes keep their options, and they are buffered until the handler
  returns.
* **A new listener is given a stale value first.** `snapshots().first` taken
  right after a write reads the state from before it. The app never sees this —
  it subscribes once on the way into a screen and stays subscribed. `_settled`
  waits for the stream to go quiet and answers with the last thing it said.

**A trading day is not a calendar day, and tests forget that at 00:30.** A test
that places an order at `DateTime.now().copyWith(hour: 12)` and then reads
"today's" rollup passes all day and fails between midnight and the store's
04:00 cutoff, because by then the wall clock's noon belongs to *tomorrow's*
trading day. `Shop.atHour()` puts a moment inside the store's current trading
day instead. Reach for it whenever a test cares which hour an order was in.

A third thing is not the fake's fault but bites in the same place: **the
stream-based harness reads must not be used inside `testWidgets`.** A widget
test runs against a fake clock that only advances when the test pumps, so a
watch awaited from the test body never settles — and a hang there kills the
whole test *file*, reporting every test after it as "did not complete" and
pointing nowhere near the cause. `_settled` now turns the microtask queue
rather than the clock and throws a named error instead of hanging;
`newestOrder()` is the one-shot `get` to reach for from a widget test.

---

## 2. Firestore rules — `cd test/rules && npm run emulate`

116 tests against a real Firestore emulator, because rules are evaluated by
Firestore and nothing else can honestly test them.

`firestore.rules` is the one file in this project that **fails silently**. A
mistake in `lib/` throws, shows a wrong number, or fails a Dart test. A mistake
there quietly lets somebody read another shop's takings, and nothing anywhere
says so.

Covered: passkey documents closed to every client in both directions; invite
codes read, issued, spent and revoked; opening a store; joining with a code;
removing somebody and what they may still do; documents written before `active`
existed; order number counters; the daily rollup; the change log; ringing up
with the server's timestamp; the five-minute window per role; an edit that
tries to move the clock to buy itself a new window; an edit that tries to
change who rang it up; and that an order is never deletable.

**The five-minute window is enforced twice on purpose.** The rules are what
actually stops a write. `mayChangeOrder` in
[lib/models/order.dart](../lib/models/order.dart) decides whether the buttons
are there at all, and is covered by `test/journey/correction_window_test.dart`.
A client that offers an edit the server then refuses is not a security hole,
but it is a shop worker tapping Save and being told no by an error code.
**Change the two together.**

---

## 3. Cloud Functions — `cd functions && npm test`

16 tests, under `node --test`. Two things, both chosen because reading the code
does not catch the mistake:

* **`normalise`** — the closed-set match that makes the slip reader a match
  against this shop's menu rather than free-text OCR wearing one as a costume.
  Whatever the model says, only ids that were on the menu it was handed may
  come out.
* **`runLadder`** — the retry ladder, under a fake clock. Its first version was
  sized on the assumption that a failing attempt costs about what a successful
  one costs. Production said a 503 from an overloaded model takes two minutes
  to arrive, and the ladder spent its whole budget on one sick model without
  ever reaching the fallbacks it existed to reach. The arithmetic was the bug,
  so the arithmetic is what is tested.

---

## 4. By hand, before a release

Nothing below can be automated from this repository, and pretending otherwise
would be worse than the list. Each entry says *why* it is here, so the list can
be argued with rather than just inherited.

### Sign-in

- [ ] **Sign in with Google.** Hands control to Google's account chooser — a
      system UI that does not exist in a Dart test process. Check the picker
      opens, that cancelling it returns to the screen rather than hanging, and
      that a brand-new Google account is offered registration rather than
      dropped into a shop it does not belong to.
- [ ] **Sign in with a passkey.** Needs the platform authenticator and a real
      fingerprint or face, plus the `passkeys` Cloud Function as relying party.
      Register one, sign out, sign in with it, then delete it. Also check the
      device with **no** enrolled biometric: it must be told, not let in.
- [ ] **A password Firebase itself rejects.** `FakeAuth` checks passwords so
      the screens' branching can be tested; whether Google's servers accept one
      is not ours to test. Worth one real wrong-password attempt per release.

### Anything with a camera or a model behind it

- [ ] **Import a menu from a photo.** Camera, App Check and the model. Try a
      blurry one: the rows it is unsure about must be the ones it asks about.
- [ ] **Scan a paper order slip.** Same path. Check a dish the shop does not
      sell never reaches the basket, and that the review screen cannot be got
      past without a decision.
- [ ] **An invite code typed on a signed-out screen.** `checkInvite` is a
      callable behind App Check, so `InviteRepository.validate` is out of reach
      of every automated suite here. The journey tests cover `redeem`, which is
      the write that actually decides the outcome.

### The device itself

- [ ] **Screen lock.** `local_auth` and the OS prompt.
- [ ] **Going offline mid-shift.** Ring up with the network off, confirm the
      order queues, come back online, confirm it sends exactly once and the
      day's takings move by exactly that order.
- [ ] **Handing the till over.** Several operators signed in at once is several
      Firebase apps, which needs a real device.
- [ ] **Exporting a workbook.** The file actually landing somewhere a person
      can find it is platform code.

---

## Known gaps

Honest list of what none of the four suites reaches today.

**The camera.** `captureMenuPhoto` opens a viewfinder, and there is no
viewfinder in a test process. Everything downstream of the shutter *is*
covered — `slip_test.dart` drives the reader from a scripted callable stream,
and `test/widgets/order_slip_review_test.dart` drives the screen that stands
between a reading and the basket — so what is untested is the handful of lines
between the two: the photo coming back and being handed on. Same for the menu
importer.

**Firebase itself.** `main.dart`, `home.dart`, `entry_screen.dart` and
`sign_in.dart` need a real `Firebase.initializeApp`, which no fake here
replaces.

**The photo menu importer.** `menu_capture_page` and
`store_settings_import_menu` are the camera path again, and unlike the slip
reader their repository half is still uncovered.

**The Menu tab's dish names.** The matrix plots dishes as dots and only names
one when it is tapped, so the screen test asserts the chart and the food-cost
figure rather than a dish label. Which dish lands in which quadrant is covered
at the data level in `analytics_test.dart`.

**Second copies of the truth.** `dailyStats` is a rollup written alongside the
orders. The journey tests check that the two agree after a sale, an edit and a
void — but nothing checks a rollup that has already drifted, because nothing
can repair one either. If a repair tool is ever written, it needs tests before
it is pointed at a real shop.

---

## 5. Would the tests notice? — mutation analysis

Everything above answers "does the app work". This answers "would we find out
if it stopped", which is a different question and the one coverage cannot touch.
Coverage says a line ran. Delete every assertion in this repository and the
coverage figure barely moves.

So the tests get tested: a defect is injected into the source, the suite is
run, and a suite that stays green has just told you it is not watching that
behaviour. `tool/mutation_rules.xml` holds the defects worth injecting, and CI
runs it over the lines a pull request touches — advisory, never blocking.

**It found two real blind spots the first time it was run**, in a suite that
caught 17 of 19 planted bugs:

* **The five-minute correction window could be changed to fifty and nothing
  failed.** Every test asked `kStaffCorrectionWindow` what the window was, so
  moving the constant moved the tests with it. The tests were true by
  construction and therefore worth nothing. What that change would really do is
  desynchronise the two halves of the rule: `firestore.rules` carries its own
  literal `duration.value(5, 'm')` and is what actually refuses the write, so a
  one-sided change gives a shop worker a live Edit button and an error code when
  they press Save. Both files said "change both" in their comments and nothing
  enforced it. There is now a test that reads the rules file and compares the
  two numbers.
* **`<` could become `<=` at the window's boundary and nothing failed.** The
  test built its order with `DateTime.now()` and the comparison read the clock
  again microseconds later, so "exactly five minutes ago" was really five
  minutes and a bit — the boundary was never actually touched and the two
  operators behaved identically. It now passes the clock in.

Neither was findable by reading the tests, and neither would have been found by
any coverage figure: both lines were covered the whole time.

### Running it

```bash
dart pub global activate mutation_test
mutation_test --rules tool/mutation_rules.xml --no-builtin lib/models/order.dart
```

**It edits your source files while it works.** An interrupted run leaves a
mutant behind — this document's own first draft was written over a working
tree with a stray `>=` turned into a `>` in `app_user.dart`, caught only by
`git status` on the way to a commit. Check `git diff` after every run, and do
not run it over uncommitted work you would mind losing.

Give it the files you changed, not the project — mutating everything takes
hours and buries the answer. A surviving mutant is a question, not a verdict:
*nothing failed when this behaviour changed — did we mean that?* Sometimes the
honest answer is yes, and the right response is to leave it.
