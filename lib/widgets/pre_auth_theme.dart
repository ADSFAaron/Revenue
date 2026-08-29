import 'package:flutter/material.dart';

import '../theme.dart';

/// Pins the screens shown before sign-in to the light palette.
///
/// Welcome, Login and Register are drawn in a deliberate black-on-white,
/// hand-sketched style — yellow and mint buttons with 1px black outlines, black
/// headings, grey helper text — which is a different design language from the
/// Material 3 shell behind the sign-in wall. Roughly forty of those colours are
/// literals rather than scheme tokens.
///
/// That was harmless while the app was hard-coded to `ThemeMode.light`. Once
/// the theme followed the system, the scaffold behind them went dark while the
/// black text on top did not, and the whole entry flow became unreadable on a
/// phone set to dark.
///
/// Two ways out: convert those forty literals to tokens, which means redrawing
/// a style that was chosen on purpose, or hold these routes in the light theme
/// until somebody decides to redesign them. This is the second. It is three
/// lines and it is honest about what it is — a holding position, not a fix.
class PreAuthTheme extends StatelessWidget {
  const PreAuthTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
        // `const TextTheme()` — the same argument main.dart passes — rather
        // than `Theme.of(context).textTheme`, which in dark mode is the white
        // typography and would have to be recoloured back. This produces the
        // app's light theme exactly.
        data: MaterialTheme(const TextTheme()).light(),
        child: child,
      );
}
