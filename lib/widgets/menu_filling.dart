import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A menu with dishes arriving in it, one after another.
///
/// The last step of registration says the menu is empty and offers three ways
/// to fix that, and until now it said only that — a heading, three buttons, and
/// nothing showing what the thing being offered actually is. This draws the
/// action: rows landing in a card until it is full, then starting over.
///
/// Drawn from the app's own vocabulary rather than illustrated. A stock drawing
/// of a person at a laptop would say "setup"; this says "your dishes go here",
/// which is the one thing the step is asking for. It is also three rectangles
/// and a circle per row, so it costs a CustomPainter rather than an asset, and
/// it takes its colours from the scheme in both modes for free.

class MenuFilling extends StatefulWidget {
  const MenuFilling({this.rows = 3, super.key});

  final int rows;

  @override
  State<MenuFilling> createState() => _MenuFillingState();
}

class _MenuFillingState extends State<MenuFilling>
    with SingleTickerProviderStateMixin {
  /// One row arriving, plus the pause at the end before it all starts again.
  static const Duration _perRow = Duration(milliseconds: 620);
  static const Duration _hold = Duration(milliseconds: 1100);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _perRow * widget.rows + _hold,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Reduced motion gets the finished picture rather than nothing: the point
    // is what a full menu looks like, and that survives holding still.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return _canvas(scheme, const AlwaysStoppedAnimation<double>(1));
    }
    return _canvas(scheme, _controller);
  }

  Widget _canvas(ColorScheme scheme, Animation<double> animation) => Semantics(
        label: 'Dishes being added to an empty menu',
        image: true,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => CustomPaint(
              painter: _MenuPainter(
                progress: animation.value,
                rows: widget.rows,
                rowShare: _perRow.inMilliseconds /
                    (_perRow.inMilliseconds * widget.rows +
                        _hold.inMilliseconds),
                scheme: scheme,
              ),
              child: const AspectRatio(aspectRatio: 3 / 2),
            ),
          ),
        ),
      );
}

class _MenuPainter extends CustomPainter {
  const _MenuPainter({
    required this.progress,
    required this.rows,
    required this.rowShare,
    required this.scheme,
  });

  final double progress;
  final int rows;

  /// How much of one cycle a single row's arrival takes.
  final double rowShare;

  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final card = Rect.fromLTWH(
      size.width * 0.14,
      size.height * 0.10,
      size.width * 0.72,
      size.height * 0.80,
    );
    final radius = Radius.circular(size.height * 0.08);

    canvas.drawRRect(
      RRect.fromRectAndRadius(card, radius),
      Paint()..color = scheme.surfaceContainerHighest,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, radius),
      Paint()
        ..color = scheme.outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final rowHeight = card.height / (rows + 1);
    final iconR = rowHeight * 0.24;

    for (var i = 0; i < rows; i++) {
      // Each row has its own slice of the cycle; the hold at the end is the
      // time after the last one lands, which is what stops it reading as a
      // loading spinner.
      final t = ((progress - i * rowShare) / rowShare).clamp(0.0, 1.0);
      if (t == 0) continue;
      final eased = Curves.easeOutCubic.transform(t);

      final y = card.top + rowHeight * (i + 0.9);
      // Arrives from the right and settles, rather than fading in on the spot —
      // a row that slides in reads as something being *put* there.
      final dx = (1 - eased) * card.width * 0.35;
      final alpha = math.min(1.0, eased * 1.6);

      final cx = card.left + card.width * 0.16 + dx;
      canvas.drawCircle(
        Offset(cx, y),
        iconR,
        Paint()..color = scheme.primary.withValues(alpha: alpha),
      );

      void bar(double startFraction, double widthFraction, double height,
          double dy, Color color) {
        final rect = Rect.fromLTWH(
          card.left + card.width * startFraction + dx,
          y + dy - height / 2,
          card.width * widthFraction,
          height,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(height / 2)),
          Paint()..color = color.withValues(alpha: alpha),
        );
      }

      // A name, a shorter line under it, and a price against the right edge —
      // the shape of a row in the menu this is standing in for.
      bar(0.28, 0.34, rowHeight * 0.17, -rowHeight * 0.13, scheme.onSurface);
      bar(0.28, 0.20, rowHeight * 0.13, rowHeight * 0.14,
          scheme.onSurfaceVariant);
      bar(0.70, 0.14, rowHeight * 0.15, 0, scheme.primary);
    }
  }

  @override
  bool shouldRepaint(_MenuPainter old) =>
      old.progress != progress || old.scheme != scheme || old.rows != rows;
}
