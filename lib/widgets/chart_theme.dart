import 'package:flutter/material.dart';

/// One palette for every chart and gauge in the app.
///
/// Before this the statistics page carried four unrelated colour systems at
/// once: Syncfusion's default blues on three column charts, a purple-to-pink
/// sweep on the gauge lifted from a Syncfusion sample, red/green pills, and the
/// app's own green. Ordered so the first entry — the one a single-series chart
/// gets — is the brand colour.
List<Color> chartPalette(ColorScheme scheme) => [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.primaryContainer,
      scheme.tertiaryContainer,
      scheme.secondaryContainer,
    ];
