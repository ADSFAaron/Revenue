import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One of the unDraw drawings, in whichever palette the theme is asking for.
///
/// Two files rather than one with a `colorFilter`: a filter tints a whole
/// picture uniformly and these have depth in them — the figure would come out
/// the same colour as the shape behind them. tool/illustration_palette.py maps
/// each of unDraw's colours to the token doing that job here and writes a copy
/// per mode; this picks between them.
class Illustration extends StatelessWidget {
  const Illustration(
    this.name, {
    this.fit = BoxFit.contain,
    this.semanticLabel,
    super.key,
  });

  /// The stem — `welcome`, `login_bg` — without the mode or the extension.
  final String name;

  final BoxFit fit;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mode =
        Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light';
    return SvgPicture.asset(
      'assets/${name}_$mode.svg',
      fit: fit,
      // Decoration. A screen reader announcing the shape of a drawing is noise
      // between the heading and the button the person came for; the few that
      // carry meaning pass a label.
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
