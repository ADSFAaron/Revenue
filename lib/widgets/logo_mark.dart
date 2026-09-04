import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'logo_geometry.dart';

/// The mark's two colours, pinned to token *values* rather than read off the
/// scheme.
///
/// The same choice tool/logo_assets.py makes, and for the same reason: this is
/// brand artwork that happens to be built from the palette, not a surface that
/// should follow it. The dark letter is not a lightened primary — #4A672D on
/// #12140E is 1.9:1 — so it moves to the container tone at 14.4:1, which is
/// exactly what the dark splash PNG does. See docs/design-tokens.md.
const Color _letterLight = Color(0xFF4A672D);
const Color _letterDark = Color(0xFFCBEEA5);
const Color _rays = Color(0xFFA8D46F);

/// The mark, drawn from [LogoGeometry].
///
/// Geometry rather than an image so the rays can move without the letter. The
/// static case costs nothing extra: it is the same painter with every ray at
/// rest.
class LogoMark extends StatelessWidget {
  const LogoMark({
    super.key,
    this.rayTravel = const [0.0, 0.0, 0.0, 0.0],
    this.rayOpacity = 1.0,
    this.letterOpacity = 1.0,
    this.scale = 1.0,
    this.semanticLabel,
  });

  /// How far each ray has slid along its own outward axis, in the mark's
  /// coordinates — [LogoGeometry.viewBox] is 1600 across, so 16 is one percent.
  final List<double> rayTravel;

  final double rayOpacity;
  final double letterOpacity;

  /// Applied about the mark's centre. Used by the exit, which grows the letter
  /// very slightly as it goes.
  final double scale;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mark = RepaintBoundary(
      child: CustomPaint(
        painter: _LogoPainter(
          letter: dark ? _letterDark : _letterLight,
          rays: _rays,
          rayTravel: rayTravel,
          rayOpacity: rayOpacity,
          letterOpacity: letterOpacity,
          scale: scale,
        ),
        // The mark keeps its own proportions whatever box it is given.
        child: const AspectRatio(aspectRatio: 1600 / 1580),
      ),
    );
    return semanticLabel == null
        ? mark
        : Semantics(label: semanticLabel, image: true, child: mark);
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({
    required this.letter,
    required this.rays,
    required this.rayTravel,
    required this.rayOpacity,
    required this.letterOpacity,
    required this.scale,
  });

  final Color letter;
  final Color rays;
  final List<double> rayTravel;
  final double rayOpacity;
  final double letterOpacity;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final box = LogoGeometry.viewBox;
    final fit = math.min(size.width / box.width, size.height / box.height);

    canvas.save();
    // Centre the mark in whatever box we were handed, then work in its own
    // coordinates from here down.
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(fit * scale);
    canvas.translate(-box.width / 2, -box.height / 2);

    // Opacity is folded into the colour rather than applied with an Opacity
    // widget: that one allocates an offscreen layer every frame, which is the
    // usual reason an otherwise trivial animation drops frames.
    if (rayOpacity > 0) {
      final paint = Paint()
        ..isAntiAlias = true
        ..color = rays.withValues(alpha: rays.a * rayOpacity);
      for (var i = 0; i < LogoGeometry.rays.length; i++) {
        final ray = LogoGeometry.rays[i];
        final travel = i < rayTravel.length ? rayTravel[i] : 0.0;
        if (travel == 0) {
          canvas.drawPath(ray.path, paint);
        } else {
          canvas.save();
          canvas.translate(ray.outward.dx * travel, ray.outward.dy * travel);
          canvas.drawPath(ray.path, paint);
          canvas.restore();
        }
      }
    }

    if (letterOpacity > 0) {
      canvas.drawPath(
        LogoGeometry.letter,
        Paint()
          ..isAntiAlias = true
          ..color = letter.withValues(alpha: letter.a * letterOpacity),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.letter != letter ||
      old.rays != rays ||
      old.rayOpacity != rayOpacity ||
      old.letterOpacity != letterOpacity ||
      old.scale != scale ||
      !_sameTravel(old.rayTravel, rayTravel);

  static bool _sameTravel(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
