package com.adsf.revenue

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity rather than FlutterActivity because `local_auth`
// shows the system biometric prompt through AndroidX BiometricPrompt, which
// requires a FragmentActivity host. On a plain FlutterActivity the plugin does
// not fail at build time — it throws at the moment somebody taps the thing
// that was supposed to be protected, which is the worst possible time to find
// out.
class MainActivity : FlutterFragmentActivity()
