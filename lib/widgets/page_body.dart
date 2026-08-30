import 'package:flutter/material.dart';

/// The width text stays comfortable to read at — near 70–80 characters.
const double kReadingWidth = 720;

/// Centres a page's content and stops it stretching on a wide window.
///
/// For content that is **not** itself the scrolling view. If the child is a
/// `ListView` or a `SingleChildScrollView`, use [ReadingWidth] instead: a
/// constraint wrapped around a scrollable narrows the scrollable, and a mouse
/// wheel over the margin beside it then does nothing, because Flutter only
/// routes pointer signals to a `Scrollable` whose box is under the pointer.
class PageBody extends StatelessWidget {
  const PageBody({
    required this.child,
    this.maxWidth = kReadingWidth,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Hands a scrollable the insets that centre its content at the reading width,
/// while the scrollable itself still fills the window.
///
/// The difference matters on a desktop or a browser. Wrapping a `ListView` in
/// a `ConstrainedBox` makes the list 720pt wide and centred; the several
/// hundred points of page either side are then dead to the mouse wheel.
/// Passing the same measurement as `padding` keeps the list full width — it
/// captures the wheel anywhere over the page — and only its rows are inset.
///
/// Measured from the incoming constraints, not the window: on a wide layout
/// the navigation rail has already taken its share.
///
/// ```dart
/// ReadingWidth(
///   builder: (context, insets) => ListView(
///     padding: insets + const EdgeInsets.symmetric(vertical: 8),
///     children: [...],
///   ),
/// )
/// ```
class ReadingWidth extends StatelessWidget {
  const ReadingWidth({
    required this.builder,
    this.maxWidth = kReadingWidth,
    super.key,
  });

  final Widget Function(BuildContext context, EdgeInsets insets) builder;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final slack = constraints.maxWidth - maxWidth;
          final inset = slack <= 0 ? 0.0 : slack / 2;
          return builder(context, EdgeInsets.symmetric(horizontal: inset));
        },
      );
}
