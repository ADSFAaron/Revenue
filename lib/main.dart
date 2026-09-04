import 'dart:async';

import 'package:flutter/material.dart';

import 'database/repositories.dart';
import 'database/session_resolver.dart';
import 'home.dart';
import 'entry/choose_path.dart';
import 'entry/entry_screen.dart';
import 'entry/idle_lock.dart';
import 'settings/screen_lock.dart';
import 'settings/theme_controller.dart';
import 'widgets/feedback.dart';
import 'widgets/opening_sequence.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Awaited, unlike the rest: it reads one key out of shared_preferences, which
  // is local and quick, and having it before the first frame is what stops the
  // app opening light and blinking to dark a moment later.
  await themeController.load();
  // Same shape and the same reason: one key out of shared_preferences, wanted
  // before the first screen that consults it. A lock that loads late is a lock
  // that is off for the first tap.
  await screenLock.load();

  // Everything that talks to the network starts here and is *not* awaited. It
  // used to be, and that was the whole of the launch gap: Firebase and App
  // Check both go out to the network, so runApp did not happen for well over a
  // second and the person watched an empty window for all of it.
  //
  // FlutterNativeSplash.preserve() was meant to cover that and could not. Its
  // entire implementation is `deferFirstFrame()` — it holds back Flutter's
  // frame and never touches the native window — so with runApp already last in
  // the queue it did nothing at all. Both calls are gone with it, which also
  // removes the web hazard the old comment described: the package's `remove()`
  // reaches for a `removeSplashFromWeb()` that only its own generator writes
  // into index.html, and threw a PlatformException out of a post-frame
  // callback on every web launch.
  //
  // What covers the wait now is the opening animation, which is what it was
  // built for. Flutter's first frame lands in a couple of hundred milliseconds
  // and draws the same mark the splash was showing.
  final services = _startServices();

  runApp(MyApp(services: services));
}

/// Firebase, its offline cache, and App Check — off the critical path.
///
/// Nothing may read from Firestore or Auth until this has finished, which is
/// why [HomePage] holds the entire auth subscription behind it rather than
/// merely showing something else in the meantime. A request that goes out
/// before App Check has activated carries no token, and with enforcement on
/// that is a refusal on the first screen.
Future<void> _startServices() async {
  // One slot, not all of them. On a device that has only ever had one person
  // on it — which is most of them — this opens the default Firebase app in
  // exactly the place and the way it always did. A second operator's slot is
  // opened when somebody taps their name, which is a local read.
  // Opening a slot also configures it — the offline cache and App Check, both
  // per app. The cache is set explicitly rather than left to each platform's
  // default: the mobile SDKs enable it, the web SDK does not, so the same shop
  // on a tablet kept working through a dropped connection and on a laptop went
  // blank. A kitchen's wifi is the case this app should assume, not the one it
  // should be surprised by.
  await sessionApps.start();
}

class MyApp extends StatelessWidget {
  const MyApp({required this.services, super.key});

  /// Firebase and App Check, still starting.
  final Future<void> services;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (context, themeMode, _) => MaterialApp(
        themeMode: themeMode,
        theme: const MaterialTheme(TextTheme()).light(),
        darkTheme: const MaterialTheme(TextTheme()).dark(),
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        // Above the Navigator rather than inside a screen: a cover that a
        // pushed route or a dialog appears on top of is not a cover.
        builder: (context, child) => IdleLock(child: child ?? const SizedBox()),
        home: HomePage(services: services),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({required this.services, super.key});

  final Future<void> services;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Whether the first real screen is built and worth uncovering.
  ///
  /// Deliberately not just "auth has answered". For somebody already signed in
  /// that answer is followed by the session gate reading their user and store
  /// documents, and exiting the opening at the earlier moment would spend the
  /// animation only to hand over to a progress circle — three states where
  /// there were two, which is worse than the spinner it replaced.
  bool _ready = false;

  /// Watches the same stream the builder below does, for one thing the builder
  /// cannot do.
  ///
  /// Signing out happens from Account & App, which is three routes deep. The
  /// stream then swaps this route's content for the welcome screen — correctly
  /// — but those three routes are still stacked on top of it, so what the
  /// person actually keeps looking at is a settings page belonging to an
  /// account that no longer exists. Every read on it fails, and the screen
  /// they are left staring at says "You do not have permission to do that".
  StreamSubscription<String?>? _signOutWatch;

  /// Who the routes above the root belong to.
  ///
  /// Null before anybody has signed in on this launch. Compared rather than
  /// merely tested, because a counter tablet can now hand over from one
  /// operator to another without passing through signed-out, and the routes
  /// the first one had open are no more the second one's than they would be
  /// after a sign-out.
  String? _routesBelongTo;

  @override
  void initState() {
    super.initState();
    // After boot, because the stream reaches FirebaseAuth.
    widget.services
        .then((_) {
          if (!mounted) return;
          _signOutWatch = authRepository.uidChanges.listen((uid) {
            final previous = _routesBelongTo;
            _routesBelongTo = uid;

            // Compared against the operator rather than tested for null: a
            // counter tablet hands over from one uid straight to another, and
            // the outgoing person's name, timeout and cover are no more the
            // incoming person's than they would be after a sign-out. Leaving
            // them set is what let the lock screen greet the new operator
            // under the old one's name.
            if (currentOperator.value?.uid != uid) {
              currentOperator.value = null;
              idleTimeout.value = Duration.zero;
              tillLocked.value = null;
            }
            // The grace period belongs to the session it was granted in.
            if (previous != uid) screenLock.relock();

            // A session being replaced or ending takes its routes with it.
            //
            // Arriving does not, and that asymmetry is the point: registration
            // creates the account partway through its own flow and still has a
            // store to create afterwards, so popping on the way *in* would
            // tear it off at exactly the moment it must not be — leaving the
            // account with no documents, which is the state this app has a
            // recovery screen for.
            if (previous != null && previous != uid) {
              navigatorKey.currentState?.popUntil((route) => route.isFirst);
            }
          });
        })
        .catchError((_) {
          // Reported by the builder below; nothing to watch if Firebase never
          // started.
        });
  }

  @override
  void dispose() {
    _signOutWatch?.cancel();
    super.dispose();
  }

  void _markReady() {
    if (_ready) return;
    // Called from inside a builder, so it cannot set state now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_ready) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OpeningSequence(
        ready: _ready,
        child: FutureBuilder<void>(
          // The gate. Firebase has to have answered before anything below can
          // ask it a question, and the opening animation is what the person
          // sees while it does.
          future: widget.services,
          builder: (context, boot) {
            if (boot.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            if (boot.hasError) {
              // Reaches the screen now instead of being an unhandled error in
              // main() that left the app on a blank window.
              _markReady();
              return ErrorView(boot.error!);
            }
            return StreamBuilder<String?>(
              // Emits the signed-in uid, or null when signed out — `hasData` is
              // false for null, so signing out falls through to the welcome
              // screen.
              stream: authRepository.uidChanges,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  // Nothing: the opening is on top of this, and a progress
                  // circle underneath would only ever be seen as a flash on
                  // its way out.
                  return const SizedBox.shrink();
                } else if (snapshot.hasData) {
                  // Keyed by the uid, so handing the till over rebuilds the
                  // whole signed-in half of the app. Everything under here —
                  // the session resolver, the shell's kept-alive pages, every
                  // Firestore stream in them — belongs to one Firebase app,
                  // and after a switch that is the wrong one.
                  //
                  // The gate is *outside* the session gate rather than inside
                  // the shell, and that placement is the fix rather than an
                  // arrangement. `_SessionGate` starts reading the moment its
                  // state is created, so a lock built any deeper than this is
                  // a lock with the shop's figures already fetched behind it.
                  return AppLockGate(
                    key: ValueKey(snapshot.data),
                    uid: snapshot.data!,
                    onLocked: _markReady,
                    child: _SessionGate(onReady: _markReady),
                  );
                } else if (snapshot.hasError) {
                  // Was `'An error occurred: ${snapshot.error}'`. This is the
                  // first screen the app ever draws, and the thing being
                  // interpolated is a `FirebaseAuthException` whose
                  // `toString()` opens with `[firebase_auth/…]` — an error
                  // code, with no next step, to somebody who has not even
                  // reached a login field.
                  _markReady();
                  return ErrorView(snapshot.error!);
                } else {
                  _markReady();
                  return const EntryScreen();
                }
              },
            );
          },
        ),
      ),
    );
  }
}

/// Holds the signed-in shell back until the user's profile and store can
/// actually be read.
///
/// Registration signs the account in the instant it is created, which happens
/// before its Firestore documents exist. Without this gate the shell mounts
/// against a half-provisioned account and every page reports "not linked to a
/// store" — and then stays that way, because each page resolves its session
/// exactly once.
class _SessionGate extends StatefulWidget {
  const _SessionGate({required this.onReady});

  /// Told when the session has resolved, one way or the other, so the opening
  /// animation knows there is something behind it worth showing.
  final VoidCallback onReady;

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late final SessionResolver _resolver = SessionResolver(
    // The write that creates the user document is what tells this to look
    // again, so there is no window between signing in and being provisioned
    // for it to fall into. See SessionResolver for what that replaced.
    changes: userRepository.watchCurrent(),
    load: loadSession,
  )..addListener(_onChange);

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _resolver
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_resolver.session != null) {
      widget.onReady();
      return const LoginHomePage();
    }
    final failure = _resolver.reportableFailure;
    if (failure != null) {
      widget.onReady();
      // A SessionException already reads as a sentence; anything else reaching
      // here is a Firestore failure whose `toString()` starts
      // `[cloud_firestore/…]`, and this is the first screen after sign-in — the
      // worst place in the app to show somebody an error code.
      return _buildError(
        context,
        describeFailure(failure).message,
        // An account with no profile is a registration that stopped halfway,
        // not a broken account. Retry cannot help it and signing out is worse
        // than useless — registering again with the same address is refused as
        // "email already in use", which left somebody locked out of their own
        // shop by the screen that was supposed to explain it.
        canFinishRegistering:
            failure is SessionException && failure.needsRegistration,
      );
    }
    // The opening animation's job on a cold start; a progress circle on a
    // retry, when the opening has long gone.
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildError(
    BuildContext context,
    String message, {
    bool canFinishRegistering = false,
  }) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                canFinishRegistering
                    ? Icons.storefront_outlined
                    : Icons.cloud_off_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (canFinishRegistering) ...[
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChoosePathScreen(
                        account: authRepository.currentSignIn(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Finish setting up'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: signOutOperator,
                  child: const Text('Sign out'),
                ),
              ] else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.tonal(
                      onPressed: _resolver.retry,
                      child: const Text('Retry'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: signOutOperator,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
