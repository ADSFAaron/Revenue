#!/usr/bin/env bash
#
# Register this device's App Check debug token with the Firebase project.
#
#     tool/register_debug_token.sh          # register
#     tool/register_debug_token.sh --show   # just print it
#
# Why this is a script rather than a note in a README:
#
# Callables run with `enforceAppCheck: true` (functions/src/config.ts), so a
# debug build whose token is not registered has every callable refused —
# deleting an account, the passkey ceremony, the menu importer. The refusal
# arrives as `unauthenticated`, which reads like a sign-in problem and is not
# one; the function's own log says it plainly:
#
#     {"verifications":{"app":"INVALID","auth":"VALID"},
#      "message":"Callable request verification failed: AppCheck token was rejected."}
#
# And the token is not stable. The Firebase SDK generates it and keeps it in the
# app's own storage, so clearing data or reinstalling produces a new one and the
# previously registered one silently stops matching. Hunting it out of logcat by
# eye every time is how an afternoon goes missing.
set -euo pipefail

PACKAGE=com.adsf.revenue
PROJECT=revenueapp-b8849
APP_ID=1:984830610429:android:338f678898416549ce2794

command -v adb >/dev/null || { echo "adb is not on PATH"; exit 1; }

echo "Restarting $PACKAGE to make it print its token…"
adb logcat -c
adb shell am force-stop "$PACKAGE"
adb shell am start -n "$PACKAGE/.MainActivity" >/dev/null

TOKEN=$(timeout 30 adb logcat -v brief 2>/dev/null \
  | grep -m1 -oE 'App Check debug token: [0-9a-f-]+' \
  | awk '{print $NF}') || true

if [ -z "${TOKEN:-}" ]; then
  echo "No debug token in the log."
  echo "Only debug builds print one — a release build uses Play Integrity and"
  echo "needs no token. Check the app actually started."
  exit 1
fi

echo "Token: $TOKEN"

if [ "${1:-}" = "--show" ]; then
  echo
  echo "firebase appcheck:debugtokens:create $TOKEN \\"
  echo "  --project $PROJECT --app $APP_ID"
  exit 0
fi

# Named after the machine so the console list stays readable, and so re-running
# this replaces the entry rather than adding a fifth one nobody can identify.
npx --prefix test/rules firebase appcheck:debugtokens:create "$TOKEN" \
  --project "$PROJECT" --app "$APP_ID"
