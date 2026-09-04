import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'logo_mark.dart';

/// How far apart the four rays start, so they read as a sweep rather than a
/// throb.
const double _stagger = 0.085;

/// One breath of the waiting pulse, in seconds.
const double _pulsePeriod = 1.8;

/// Pulse amplitude, in the mark's own units — the viewBox is 1600 across, so
/// this is about two percent. Enough to be alive, not enough to be a feature:
/// on a phone it is three or four points of travel.
const double _amplitude = 34;

/// Carries the launch from the native splash into the app, and stands in for
/// the loading indicator while it does.
///
/// The native splash is a static picture of the mark on the surface colour, and
/// the two colours already match exactly (docs/design-tokens.md). So the first
/// Flutter frame draws the same mark on the same ground, and the animation is
/// necessarily an *exit* rather than an entrance — anything that assembled the
/// mark would have to take apart a mark the person is already looking at.
///
/// The mark is also the spinner. While the app is still working out who is
/// signed in and which shop that is, the rays travel gently outward and back,
/// staggered, and the amplitude ramps up from nothing so the first frame is
/// identical to the still image it took over from. A shop opening the app on a
/// bad connection waits on its own logo rather than on a progress circle.
///
/// Nothing here lengthens a launch: [ready] is driven by work that had to
/// happen anyway, and the only time this adds is [_minimumHold], which exists
/// so that a fast launch does not flash the mark for two frames.
class OpeningSequence extends StatefulWidget {
  const OpeningSequence({
    required this.ready,
    required this.child,
    super.key,
  });

  /// Whether the first real screen is built and worth showing.
  final bool ready;

  final Widget child;

  @override
  State<OpeningSequence> createState() => _OpeningSequenceState();
}

class _OpeningSequenceState extends State<OpeningSequence>
    with SingleTickerProviderStateMixin {
  /// Held even on an instant launch, so the mark cannot appear for two frames
  /// and vanish.
  static const Duration _minimumHold = Duration(milliseconds: 320);

  static const Duration _exit = Duration(milliseconds: 460);

  /// How far the rays fly on the way out.
  static const double _exitTravel = 210;

  late final Ticker _ticker = createTicker(_tick);

  /// Drives the overlay alone. A `setState` per frame would rebuild [child]
  /// too — the entire app screen, sitting underneath — sixty times a second
  /// for an animation that only touches four paths.
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);

  Duration? _exitStartedAt;
  Duration _now = Duration.zero;
  bool _held = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void didUpdateWidget(OpeningSequence old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) _maybeExit();
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    if (!_held && elapsed >= _minimumHold) {
      _held = true;
      _maybeExit();
    }
    if (_exitStartedAt != null &&
        elapsed - _exitStartedAt! >= _exit &&
        !_done) {
      _done = true;
      _ticker.stop();
      setState(() {});
      return;
    }
    _clock.value = elapsed.inMicroseconds / 1000000;
  }

  void _maybeExit() {
    if (_exitStartedAt != null || !_held || !widget.ready) return;
    _exitStartedAt = _now;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Reduced motion is not "no splash": the handover still has to happen, and
    // a hard cut from the native splash to the app is exactly the jolt the
    // setting exists to avoid. What goes is the movement — the mark holds
    // still and the ground fades.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Stack(
      children: [
        widget.child,
        // Dropped from the list when it is finished, never by returning
        // widget.child on its own. Returning the child directly changes its
        // parent — Stack one frame, the Scaffold's body slot the next — and
        // Flutter rebuilds an element whose position in the tree has moved.
        // That took the StreamBuilder above with it: it re-subscribed to the
        // auth stream, went back to `waiting`, and drew the empty box it draws
        // while waiting. The app opened, animated, handed over, and landed on
        // a blank screen with nothing in any log.
        //
        // SizedBox.expand rather than Positioned.fill, which is a second thing
        // the same shape. A Stack takes its size from its *non-positioned*
        // children, and while auth is still answering that child has no size,
        // so a Positioned.fill overlay filled a 0x0 Stack. Expanding here makes
        // the overlay the child that gives the Stack its size, and leaves
        // widget.child on the loose constraints it would have had as the body.
        if (!_done)
          SizedBox.expand(
            child: ValueListenableBuilder<double>(
              valueListenable: _clock,
              builder: (context, seconds, _) =>
                  _overlay(context, scheme, seconds, still),
            ),
          ),
      ],
    );
  }

  Widget _overlay(
    BuildContext context,
    ColorScheme scheme,
    double seconds,
    bool still,
  ) {
    final exitStart = _exitStartedAt;
    final exit = exitStart == null
        ? 0.0
        : ((seconds - exitStart.inMicroseconds / 1000000) /
                (_exit.inMicroseconds / 1000000))
            .clamp(0.0, 1.0);

    // Everything below is a slice of one 0..1 exit. Written as explicit
    // windows rather than a stack of controllers because the whole point is
    // that the rays leave before the letter does and the ground leaves last —
    // an order that is much easier to read as three numbers than as three
    // objects.
    final rayGo = Curves.easeOutCubic.transform(_window(exit, 0.0, 0.62));
    final letterGo = Curves.easeOut.transform(_window(exit, 0.10, 0.58));
    // Overlaps the letter's own fade rather than following it. Starting the
    // ground at 0.55 left a beat of empty surface between the mark leaving and
    // the app arriving — one frame of nothing, which reads as a stall. The two
    // now cross over each other.
    final groundGo = Curves.easeInOut.transform(_window(exit, 0.40, 1.0));

    final travel = <double>[
      for (var i = 0; i < 4; i++)
        (still ? 0.0 : openingRayTravel(seconds, i)) + _exitTravel * rayGo,
    ];

    return IgnorePointer(
      child: ColoredBox(
        color: scheme.surface.withValues(alpha: 1 - groundGo),
        child: Center(
          child: FractionallySizedBox(
            // Not an attempt to match the native splash pixel for pixel: that
            // size is set three different ways (an Android 12 icon in a 768px
            // circle, a centred bitmap below that, an iOS image set) and
            // landing between them would read as a jump rather than as a
            // continuation. The colour is what carries the handover, and the
            // colour is exact.
            widthFactor: 0.42,
            child: LogoMark(
              semanticLabel: 'Revenue',
              rayTravel: travel,
              rayOpacity: 1 - rayGo,
              letterOpacity: 1 - letterGo,
              scale: 1 + 0.05 * letterGo,
            ),
          ),
        ),
      ),
    );
  }

  /// Where [t] sits inside [from]..[to], as 0..1.
  static double _window(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

}

/// Ray [index]'s resting travel at [seconds] of waiting, in the mark's own
/// units.
///
/// Top-level and visible so the property this whole design rests on can be
/// asserted rather than described: at zero seconds every ray is at zero, so the
/// first Flutter frame is the still image it took over from, pixel for pixel.
///
/// That is what the ramp is for. The four rays are staggered so they read as a
/// sweep rather than a throb, and a staggered ray would otherwise open
/// part-way through its own cycle — every ray but the first would jump on the
/// first frame. Ramping the amplitude in over one period starts them all from
/// nothing and still loops cleanly afterwards.
@visibleForTesting
double openingRayTravel(double seconds, int index) {
  final ramp = math.min(1.0, seconds / _pulsePeriod);
  final phase = (seconds / _pulsePeriod - index * _stagger) % 1.0;
  return _amplitude * ramp * (1 - math.cos(2 * math.pi * phase)) / 2;
}
