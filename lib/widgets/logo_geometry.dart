// GENERATED FILE — do not edit by hand.
//
// Written by tool/logo_svg.py from the measurements documented there, which
// also writes assets/icon/AppLogo.svg. Re-run that script after changing the
// mark; the two outputs share one set of numbers so they cannot disagree.

import 'dart:ui';

/// One ray, with the direction it points away from the letter.
class LogoRay {
  const LogoRay({required this.path, required this.outward});

  final Path path;

  /// A unit vector in the mark's own coordinates. The opening animation slides
  /// each ray along this, which is what makes them read as light leaving the
  /// letter rather than as a picture being scaled.
  final Offset outward;
}

/// The mark as geometry, in its own 1600x1580 coordinate space.
class LogoGeometry {
  const LogoGeometry._();

  /// The box the paths below are drawn in. Scale to fit, do not assume pixels.
  static const Size viewBox = Size(1600, 1580);

  /// The letter, as one path. The parts overlap in area rather than meeting
  /// along shared edges — two antialiased shapes that merely touch leave a
  /// hairline seam between them however identical their fill.
  static final Path letter = Path()
    ..addPath(_top, Offset.zero)
    ..addPath(_stem, Offset.zero)
    ..addPath(_bowl, Offset.zero)
    ..addPath(_leg, Offset.zero)
    ..addOval(Rect.fromCircle(
        center: const Offset(421.5, 865.4), radius: 120.9));

  static final Path _top = Path()
    ..moveTo(76.0, 335.6)
    ..lineTo(473.9, 335.6)
      ..arcToPoint(const Offset(756.1, 484.2), radius: const Radius.circular(342.2), largeArc: false, clockwise: true)
    ..lineTo(76.0, 484.2)
    ..close();

  static final Path _stem = Path()
    ..addRect(const Rect.fromLTRB(
        76.0, 335.6, 226.0, 1472.0));

  static final Path _bowl = Path()
    ..moveTo(473.9, 335.6)
      ..arcToPoint(const Offset(684.3, 947.6), radius: const Radius.circular(342.2), largeArc: false, clockwise: true)
    ..lineTo(580.8, 839.2)
      ..arcToPoint(const Offset(473.9, 484.2), radius: const Radius.circular(193.6), largeArc: false, clockwise: false)
    ..close();

  static final Path _leg = Path()
    ..moveTo(306.7, 865.4)
    ..lineTo(491.6, 865.4)
    ..lineTo(1080.2, 1472.0)
    ..lineTo(877.6, 1472.0)
    ..close();

  /// Ray 1, and the direction it travels away from the letter.
  static final LogoRay ray1 = LogoRay(
    path: Path()
      ..moveTo(1496.8, 522.0)
      ..arcToPoint(const Offset(1508.1, 492.0), radius: const Radius.circular(22.0), largeArc: false, clockwise: true)
      ..lineTo(1463.2, 400.8)
      ..arcToPoint(const Offset(1432.6, 391.3), radius: const Radius.circular(22.0), largeArc: false, clockwise: true)
      ..lineTo(931.6, 676.0)
      ..arcToPoint(const Offset(922.7, 704.8), radius: const Radius.circular(22.0), largeArc: false, clockwise: true)
      ..lineTo(937.2, 734.1)
      ..arcToPoint(const Offset(965.4, 744.7), radius: const Radius.circular(22.0), largeArc: false, clockwise: true)
      ..close(),
    outward: const Offset(0.8975, -0.4410),
  );

  /// Ray 2, and the direction it travels away from the letter.
  static final LogoRay ray2 = LogoRay(
    path: Path()
      ..moveTo(1326.2, 190.7)
      ..arcToPoint(const Offset(1325.1, 163.1), radius: const Radius.circular(19.0), largeArc: false, clockwise: true)
      ..lineTo(1243.9, 92.1)
      ..arcToPoint(const Offset(1216.4, 94.6), radius: const Radius.circular(19.0), largeArc: false, clockwise: true)
      ..lineTo(888.1, 512.5)
      ..arcToPoint(const Offset(890.6, 538.6), radius: const Radius.circular(19.0), largeArc: false, clockwise: true)
      ..lineTo(929.4, 572.6)
      ..arcToPoint(const Offset(955.6, 571.6), radius: const Radius.circular(19.0), largeArc: false, clockwise: true)
      ..close(),
    outward: const Offset(0.6585, -0.7526),
  );

  /// Ray 3, and the direction it travels away from the letter.
  static final LogoRay ray3 = LogoRay(
    path: Path()
      ..moveTo(1455.9, 889.9)
      ..arcToPoint(const Offset(1477.4, 866.0), radius: const Radius.circular(22.0), largeArc: false, clockwise: true)
      ..lineTo(1468.0, 758.5)
      ..arcToPoint(const Offset(1442.6, 738.7), radius: const Radius.circular(22.0), largeArc: false, clockwise: true)
      ..lineTo(910.0, 823.2)
      ..arcToPoint(const Offset(891.5, 846.8), radius: const Radius.circular(22.0), largeArc: false, clockwise: true)
      ..lineTo(894.4, 879.6)
      ..arcToPoint(const Offset(916.7, 899.6), radius: const Radius.circular(22.0), largeArc: false, clockwise: true)
      ..close(),
    outward: const Offset(0.9962, -0.0875),
  );

  /// Ray 4, and the direction it travels away from the letter.
  static final LogoRay ray4 = LogoRay(
    path: Path()
      ..moveTo(850.8, 961.6)
      ..arcToPoint(const Offset(819.2, 974.1), radius: const Radius.circular(25.0), largeArc: false, clockwise: true)
      ..lineTo(805.8, 1002.2)
      ..arcToPoint(const Offset(815.8, 1034.7), radius: const Radius.circular(25.0), largeArc: false, clockwise: true)
      ..lineTo(1166.2, 1237.1)
      ..arcToPoint(const Offset(1201.3, 1226.2), radius: const Radius.circular(25.0), largeArc: false, clockwise: true)
      ..lineTo(1241.9, 1141.2)
      ..arcToPoint(const Offset(1228.3, 1107.1), radius: const Radius.circular(25.0), largeArc: false, clockwise: true)
      ..close(),
    outward: const Offset(0.9022, 0.4312),
  );

  static final List<LogoRay> rays = [ray1, ray2, ray3, ray4];
}
