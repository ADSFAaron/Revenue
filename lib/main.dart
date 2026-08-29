import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'animation/FadeAnimation.dart';
import 'database/repositories.dart';
import 'firebase_options.dart';
import 'home.dart';
import 'login.dart';
import 'register.dart';
import 'settings/theme_controller.dart';
import 'widgets/pre_auth_theme.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Offline cache, set explicitly rather than left to each platform's
  // default. The mobile SDKs enable it; the web SDK does not, so the same shop
  // on a tablet kept working through a dropped connection and on a laptop went
  // blank. A kitchen's wifi is the case this app should assume, not the one it
  // should be surprised by.
  configureFirestore();

  // Read before the first frame, so the app does not open light and then blink
  // to dark a moment later.
  await themeController.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
        home: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<String?>(
        // Emits the signed-in uid, or null when signed out — `hasData` is
        // false for null, so signing out falls through to the welcome screen.
        stream: authRepository.uidChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasData) {
            return const _SessionGate();
          } else if (snapshot.hasError) {
            return Center(
              child: Text(
                'An error occurred: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          } else {
            return const WelcomeScreen();
          }
        },
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
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late Future<Session> _session = _resolve();

  /// Retries briefly: the user document lands a moment after sign-in, and that
  /// window is the only case worth waiting through. A genuine failure — no
  /// store, no permission — still surfaces after a second or so.
  Future<Session> _resolve() async {
    for (var attempt = 0;; attempt++) {
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
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          // A SessionException already reads as a sentence; anything else
          // reaching here is a Firestore failure whose `toString()` starts
          // `[cloud_firestore/…]`, and this is the first screen after sign-in
          // — the worst place in the app to show somebody an error code.
          return _buildError(describeFailure(snapshot.error!).message);
        }
        return const LoginHomePage();
      },
    );
  }

  Widget _buildError(String message) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
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
    );
  }

  Widget _buildWelcomeMessage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        FadeAnimation(
          0,
          const Text(
            'Welcome',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 10),
        FadeAnimation(
          100,
          const Text(
            'Please login to continue',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey,
            ),
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

  Widget _buildButton({
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
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
    );
  }
}
