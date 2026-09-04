import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'animation/fade_animation.dart';
import 'database/repositories.dart';
import 'firebase_options.dart';
import 'home.dart';
import 'login.dart';
import 'register.dart';
import 'settings/theme_controller.dart';
import 'widgets/feedback.dart';
import 'widgets/opening_sequence.dart';
import 'widgets/page_body.dart';
import 'widgets/pre_auth_theme.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Awaited, unlike the rest: it reads one key out of shared_preferences, which
  // is local and quick, and having it before the first frame is what stops the
  // app opening light and blinking to dark a moment later.
  await themeController.load();

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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Offline cache, set explicitly rather than left to each platform's
  // default. The mobile SDKs enable it; the web SDK does not, so the same shop
  // on a tablet kept working through a dropped connection and on a laptop went
  // blank. A kitchen's wifi is the case this app should assume, not the one it
  // should be surprised by.
  configureFirestore();
  await configureAppCheck();
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
              // false for null, so signing out falls through to the welcome screen.
              stream: authRepository.uidChanges,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  // Nothing: the opening is on top of this, and a progress circle
                  // underneath would only ever be seen as a flash on its way out.
                  return const SizedBox.shrink();
                } else if (snapshot.hasData) {
                  return _SessionGate(onReady: _markReady);
                } else if (snapshot.hasError) {
                  // Was `'An error occurred: ${snapshot.error}'`. This is the first
                  // screen the app ever draws, and the thing being interpolated is a
                  // `FirebaseAuthException` whose `toString()` opens with
                  // `[firebase_auth/…]` — an error code, with no next step, to
                  // somebody who has not even reached a login field. The session
                  // gate fifty lines below already does this properly; this is the
                  // one place that was still doing it by hand.
                  _markReady();
                  return ErrorView(snapshot.error!);
                } else {
                  _markReady();
                  return const WelcomeScreen();
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
  late Future<Session> _session = _resolve();

  /// Retries briefly: the user document lands a moment after sign-in, and that
  /// window is the only case worth waiting through. A genuine failure — no
  /// store, no permission — still surfaces after a second or so.
  Future<Session> _resolve() async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await loadSession();
      } on SessionException {
        if (attempt >= 4) rethrow;
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Session>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Kept, rather than blanked like the auth wait above: this builder
          // runs again on Retry, long after the opening has gone.
          return const Center(child: CircularProgressIndicator());
        }
        widget.onReady();
        if (snapshot.hasError) {
          // A SessionException already reads as a sentence; anything else
          // reaching here is a Firestore failure whose `toString()` starts
          // `[cloud_firestore/…]`, and this is the first screen after sign-in
          // — the worst place in the app to show somebody an error code.
          return _buildError(context, describeFailure(snapshot.error!).message);
        }
        return const LoginHomePage();
      },
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.tonal(
                    onPressed: () => setState(() => _session = _resolve()),
                    child: const Text('Retry'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: authRepository.signOut,
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

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Its own Scaffold, inside PreAuthTheme: the background this draws on has
    // to come from the light palette too, and the Scaffold above this one
    // belongs to the signed-in half of the app.
    return PreAuthTheme(
      child: Scaffold(
        body: SafeArea(
          child: PageBody(
            maxWidth: 480,
            child: Container(
              width: double.infinity,
              height: MediaQuery.of(context).size.height,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 50),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _buildWelcomeMessage(context),
                  _buildAuthButtons(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeMessage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        FadeAnimation(
          0,
          Text(
            'Welcome',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 10),
        FadeAnimation(
          100,
          Text(
            'Please login to continue',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: Colors.grey),
          ),
        ),
        const SizedBox(height: 20),
        FadeAnimation(
          500,
          SizedBox(
            height: MediaQuery.of(context).size.height / 3,
            child: SvgPicture.asset('assets/welcome.svg'),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildAuthButtons(BuildContext context) {
    return Column(
      children: <Widget>[
        FadeAnimation(
          750,
          _buildButton(
            context,
            text: 'Login',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        FadeAnimation(
          1000,
          _buildButton(
            context,
            text: 'Register',
            color: Colors.yellow,
            textColor: Colors.black,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RegisterPage()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildButton(
    BuildContext context, {
    required String text,
    required VoidCallback onPressed,
    Color color = Colors.transparent,
    Color textColor = Colors.black,
  }) {
    return MaterialButton(
      height: 60,
      minWidth: double.infinity,
      onPressed: onPressed,
      color: color,
      textColor: textColor,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Colors.black),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
