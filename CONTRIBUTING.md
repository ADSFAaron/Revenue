# Contributing

Thanks for looking. A few things are worth knowing before you spend an evening
on a branch.

## Before you write code

**Open an issue first for anything larger than a fix.** This is one shop
owner's till with real shops on it, and the constraints that decide most design
questions here — Firestore has no `GROUP BY`, so every report needs a
pre-aggregated table; a screen may never touch `FirebaseFirestore.instance`;
anything that touches money has to say whether it is live or cached — are not
obvious from the outside. It is much cheaper to find out in an issue than in a
review.

## Licensing — please read this before your first pull request

This project is **AGPL-3.0** ([LICENSE](LICENSE)). Contributions come in under
the same licence: what goes in is what comes out.

**The authors may in future offer this code under a separate commercial
licence.** That is only possible for code the authors hold the copyright to, so
a pull request may be asked to come with a contributor licence agreement
granting the maintainers the right to relicense it. There is no CLA in place
today. If one is introduced it will appear here first, and it will never be
applied retroactively to work already merged.

If you are not comfortable with that, say so on the issue before you start —
a contribution can usually be restructured so the question does not arise, and
that is a far better outcome than a finished branch nobody can merge.

## Ground rules in this codebase

* **No widget references Firebase.** Every read and write goes through a
  repository in `lib/database/`. `firebase_auth`, `cloud_functions` and
  `passkeys` are confined there too. See *The repository layer* in the README.
* **The security rules are the security model.** A screen hiding a button is a
  courtesy; `firestore.rules` is what refuses the write. If a change needs a
  new permission, the rule and the UI move together.
* **An unknown number is shown as unknown.** A dish with no cost is left out of
  margin figures rather than counted as free. A cached figure says it is
  cached. Nothing about money is estimated quietly.
* **Comments explain why, not what.** The existing ones are long on purpose —
  most record a bug that the obvious version of the code caused. Match that.
* **Errors reach people as sentences.** Never `${snapshot.error}` on screen;
  use `describeFailure` / `ErrorView` from `lib/widgets/feedback.dart`.

## Checks

Everything below has to pass, and the analyzer must not gain new issues:

```bash
flutter analyze
flutter test
flutter build apk --debug     # if you touched a plugin or anything under android/
```

Tests live beside what they cover in `test/`. A bug fix wants a test that fails
without it.

## Pull requests

1. Fork, then branch from `main` (`git checkout -b feature/AmazingFeature`).
2. Keep the change to one subject. A refactor riding along with a feature is
   two reviews wearing one hat.
3. Say in the description what a person would *do differently* because of it.
4. Open the PR.
