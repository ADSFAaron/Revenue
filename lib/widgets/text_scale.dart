import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// How big a fixed-size box has to be to still hold its text at the reader's
/// font size.
///
/// Flutter grows every `Text` by the system font setting on its own — that
/// part needs no help, and is why sizes should come from the text theme rather
/// than from a `fontSize:` written at the call site. What does not move is the
/// furniture around the text: a `width: 44` for a column of figures, a 24pt
/// circle around a numeral, the gutter an axis reserves for its labels. Those
/// are the places text gets clipped when somebody turns the slider up, and the
/// fix is to ask for the measurement rather than write it down.
///
/// [cap] is for the few places where the space is genuinely contested — a
/// heat map is twenty-four cells wide whatever the font is, and past about
/// 1.6x the cells are pushed off the side of the phone faster than the
/// numerals in them are helped. A box that only has to hold its own text takes
/// the full scale and leaves [cap] alone.
double scaledForText(
  BuildContext context,
  double size, {
  double cap = double.infinity,
}) =>
    math.min(MediaQuery.textScalerOf(context).scale(size), size * cap);
