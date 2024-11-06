import "package:flutter/material.dart";

class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  static ColorScheme lightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(4283066157),
      surfaceTint: Color(4283066157),
      onPrimary: Color(4294967295),
      primaryContainer: Color(4291554981),
      onPrimaryContainer: Color(4279115776),
      secondary: Color(4283916874),
      onSecondary: Color(4294967295),
      secondaryContainer: Color(4292601800),
      onSecondaryContainer: Color(4279574027),
      tertiary: Color(4281886308),
      onTertiary: Color(4294967295),
      tertiaryContainer: Color(4290505960),
      onTertiaryContainer: Color(4278198303),
      error: Color(4290386458),
      onError: Color(4294967295),
      errorContainer: Color(4294957782),
      onErrorContainer: Color(4282449922),
      surface: Color(4294572783),
      onSurface: Color(4279901206),
      onSurfaceVariant: Color(4282665021),
      outline: Color(4285823340),
      outlineVariant: Color(4291086522),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4281282858),
      inversePrimary: Color(4289778059),
      primaryFixed: Color(4291554981),
      onPrimaryFixed: Color(4279115776),
      primaryFixedDim: Color(4289778059),
      onPrimaryFixedVariant: Color(4281552407),
      secondaryFixed: Color(4292601800),
      onSecondaryFixed: Color(4279574027),
      secondaryFixedDim: Color(4290759597),
      onSecondaryFixedVariant: Color(4282403380),
      tertiaryFixed: Color(4290505960),
      onTertiaryFixed: Color(4278198303),
      tertiaryFixedDim: Color(4288729036),
      onTertiaryFixedVariant: Color(4280241740),
      surfaceDim: Color(4292467664),
      surfaceBright: Color(4294572783),
      surfaceContainerLowest: Color(4294967295),
      surfaceContainerLow: Color(4294178281),
      surfaceContainer: Color(4293783524),
      surfaceContainerHigh: Color(4293454302),
      surfaceContainerHighest: Color(4293059544),
    );
  }

  ThemeData light() {
    return theme(lightScheme());
  }

  static ColorScheme lightMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(4281289235),
      surfaceTint: Color(4283066157),
      onPrimary: Color(4294967295),
      primaryContainer: Color(4284513601),
      onPrimaryContainer: Color(4294967295),
      secondary: Color(4282140208),
      onSecondary: Color(4294967295),
      secondaryContainer: Color(4285364319),
      onSecondaryContainer: Color(4294967295),
      tertiary: Color(4279913032),
      onTertiary: Color(4294967295),
      tertiaryContainer: Color(4283399290),
      onTertiaryContainer: Color(4294967295),
      error: Color(4287365129),
      onError: Color(4294967295),
      errorContainer: Color(4292490286),
      onErrorContainer: Color(4294967295),
      surface: Color(4294572783),
      onSurface: Color(4279901206),
      onSurfaceVariant: Color(4282401850),
      outline: Color(4284244309),
      outlineVariant: Color(4286086256),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4281282858),
      inversePrimary: Color(4289778059),
      primaryFixed: Color(4284513601),
      onPrimaryFixed: Color(4294967295),
      primaryFixedDim: Color(4282934315),
      onPrimaryFixedVariant: Color(4294967295),
      secondaryFixed: Color(4285364319),
      onSecondaryFixed: Color(4294967295),
      secondaryFixedDim: Color(4283785288),
      onSecondaryFixedVariant: Color(4294967295),
      tertiaryFixed: Color(4283399290),
      onTertiaryFixed: Color(4294967295),
      tertiaryFixedDim: Color(4281754465),
      onTertiaryFixedVariant: Color(4294967295),
      surfaceDim: Color(4292467664),
      surfaceBright: Color(4294572783),
      surfaceContainerLowest: Color(4294967295),
      surfaceContainerLow: Color(4294178281),
      surfaceContainer: Color(4293783524),
      surfaceContainerHigh: Color(4293454302),
      surfaceContainerHighest: Color(4293059544),
    );
  }

  ThemeData lightMediumContrast() {
    return theme(lightMediumContrastScheme());
  }

  static ColorScheme lightHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(4279445248),
      surfaceTint: Color(4283066157),
      onPrimary: Color(4294967295),
      primaryContainer: Color(4281289235),
      onPrimaryContainer: Color(4294967295),
      secondary: Color(4280034578),
      onSecondary: Color(4294967295),
      secondaryContainer: Color(4282140208),
      onSecondaryContainer: Color(4294967295),
      tertiary: Color(4278200102),
      onTertiary: Color(4294967295),
      tertiaryContainer: Color(4279913032),
      onTertiaryContainer: Color(4294967295),
      error: Color(4283301890),
      onError: Color(4294967295),
      errorContainer: Color(4287365129),
      onErrorContainer: Color(4294967295),
      surface: Color(4294572783),
      onSurface: Color(4278190080),
      onSurfaceVariant: Color(4280362268),
      outline: Color(4282401850),
      outlineVariant: Color(4282401850),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4281282858),
      inversePrimary: Color(4292212654),
      primaryFixed: Color(4281289235),
      onPrimaryFixed: Color(4294967295),
      primaryFixedDim: Color(4279907072),
      onPrimaryFixedVariant: Color(4294967295),
      secondaryFixed: Color(4282140208),
      onSecondaryFixed: Color(4294967295),
      secondaryFixedDim: Color(4280692763),
      onSecondaryFixedVariant: Color(4294967295),
      tertiaryFixed: Color(4279913032),
      onTertiaryFixed: Color(4294967295),
      tertiaryFixedDim: Color(4278203185),
      onTertiaryFixedVariant: Color(4294967295),
      surfaceDim: Color(4292467664),
      surfaceBright: Color(4294572783),
      surfaceContainerLowest: Color(4294967295),
      surfaceContainerLow: Color(4294178281),
      surfaceContainer: Color(4293783524),
      surfaceContainerHigh: Color(4293454302),
      surfaceContainerHighest: Color(4293059544),
    );
  }

  ThemeData lightHighContrast() {
    return theme(lightHighContrastScheme());
  }

  static ColorScheme darkScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(4289778059),
      surfaceTint: Color(4289778059),
      onPrimary: Color(4280170242),
      primaryContainer: Color(4281552407),
      onPrimaryContainer: Color(4291554981),
      secondary: Color(4290759597),
      onSecondary: Color(4280955679),
      secondaryContainer: Color(4282403380),
      onSecondaryContainer: Color(4292601800),
      tertiary: Color(4288729036),
      onTertiary: Color(4278204213),
      tertiaryContainer: Color(4280241740),
      onTertiaryContainer: Color(4290505960),
      error: Color(4294948011),
      onError: Color(4285071365),
      errorContainer: Color(4287823882),
      onErrorContainer: Color(4294957782),
      surface: Color(4279374862),
      onSurface: Color(4293059544),
      onSurfaceVariant: Color(4291086522),
      outline: Color(4287533701),
      outlineVariant: Color(4282665021),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4293059544),
      inversePrimary: Color(4283066157),
      primaryFixed: Color(4291554981),
      onPrimaryFixed: Color(4279115776),
      primaryFixedDim: Color(4289778059),
      onPrimaryFixedVariant: Color(4281552407),
      secondaryFixed: Color(4292601800),
      onSecondaryFixed: Color(4279574027),
      secondaryFixedDim: Color(4290759597),
      onSecondaryFixedVariant: Color(4282403380),
      tertiaryFixed: Color(4290505960),
      onTertiaryFixed: Color(4278198303),
      tertiaryFixedDim: Color(4288729036),
      onTertiaryFixedVariant: Color(4280241740),
      surfaceDim: Color(4279374862),
      surfaceBright: Color(4281809459),
      surfaceContainerLowest: Color(4278980361),
      surfaceContainerLow: Color(4279901206),
      surfaceContainer: Color(4280164634),
      surfaceContainerHigh: Color(4280822564),
      surfaceContainerHighest: Color(4281546286),
    );
  }

  ThemeData dark() {
    return theme(darkScheme());
  }

  static ColorScheme darkMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(4290041231),
      surfaceTint: Color(4289778059),
      onPrimary: Color(4278917632),
      primaryContainer: Color(4286290522),
      onPrimaryContainer: Color(4278190080),
      secondary: Color(4291022769),
      onSecondary: Color(4279245063),
      secondaryContainer: Color(4287206778),
      onSecondaryContainer: Color(4278190080),
      tertiary: Color(4288992464),
      onTertiary: Color(4278196761),
      tertiaryContainer: Color(4285241750),
      onTertiaryContainer: Color(4278190080),
      error: Color(4294949553),
      onError: Color(4281794561),
      errorContainer: Color(4294923337),
      onErrorContainer: Color(4278190080),
      surface: Color(4279374862),
      onSurface: Color(4294638832),
      onSurfaceVariant: Color(4291415230),
      outline: Color(4288783511),
      outlineVariant: Color(4286678392),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4293059544),
      inversePrimary: Color(4281618200),
      primaryFixed: Color(4291554981),
      onPrimaryFixed: Color(4278653952),
      primaryFixedDim: Color(4289778059),
      onPrimaryFixedVariant: Color(4280499463),
      secondaryFixed: Color(4292601800),
      onSecondaryFixed: Color(4278916100),
      secondaryFixedDim: Color(4290759597),
      onSecondaryFixedVariant: Color(4281284900),
      tertiaryFixed: Color(4290505960),
      onTertiaryFixed: Color(4278195220),
      tertiaryFixedDim: Color(4288729036),
      onTertiaryFixedVariant: Color(4278730043),
      surfaceDim: Color(4279374862),
      surfaceBright: Color(4281809459),
      surfaceContainerLowest: Color(4278980361),
      surfaceContainerLow: Color(4279901206),
      surfaceContainer: Color(4280164634),
      surfaceContainerHigh: Color(4280822564),
      surfaceContainerHighest: Color(4281546286),
    );
  }

  ThemeData darkMediumContrast() {
    return theme(darkMediumContrastScheme());
  }

  static ColorScheme darkHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(4294246369),
      surfaceTint: Color(4289778059),
      onPrimary: Color(4278190080),
      primaryContainer: Color(4290041231),
      onPrimaryContainer: Color(4278190080),
      secondary: Color(4294246369),
      onSecondary: Color(4278190080),
      secondaryContainer: Color(4291022769),
      onSecondaryContainer: Color(4278190080),
      tertiary: Color(4293591037),
      onTertiary: Color(4278190080),
      tertiaryContainer: Color(4288992464),
      onTertiaryContainer: Color(4278190080),
      error: Color(4294965753),
      onError: Color(4278190080),
      errorContainer: Color(4294949553),
      onErrorContainer: Color(4278190080),
      surface: Color(4279374862),
      onSurface: Color(4294967295),
      onSurfaceVariant: Color(4294573293),
      outline: Color(4291415230),
      outlineVariant: Color(4291415230),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4293059544),
      inversePrimary: Color(4279775232),
      primaryFixed: Color(4291818153),
      onPrimaryFixed: Color(4278190080),
      primaryFixedDim: Color(4290041231),
      onPrimaryFixedVariant: Color(4278917632),
      secondaryFixed: Color(4292864972),
      onSecondaryFixed: Color(4278190080),
      secondaryFixedDim: Color(4291022769),
      onSecondaryFixedVariant: Color(4279245063),
      tertiaryFixed: Color(4290834669),
      onTertiaryFixed: Color(4278190080),
      tertiaryFixedDim: Color(4288992464),
      onTertiaryFixedVariant: Color(4278196761),
      surfaceDim: Color(4279374862),
      surfaceBright: Color(4281809459),
      surfaceContainerLowest: Color(4278980361),
      surfaceContainerLow: Color(4279901206),
      surfaceContainer: Color(4280164634),
      surfaceContainerHigh: Color(4280822564),
      surfaceContainerHighest: Color(4281546286),
    );
  }

  ThemeData darkHighContrast() {
    return theme(darkHighContrastScheme());
  }


  ThemeData theme(ColorScheme colorScheme) => ThemeData(
     useMaterial3: true,
     brightness: colorScheme.brightness,
     colorScheme: colorScheme,
     textTheme: textTheme.apply(
       bodyColor: colorScheme.onSurface,
       displayColor: colorScheme.onSurface,
     ),
     scaffoldBackgroundColor: colorScheme.background,
     canvasColor: colorScheme.surface,
  );


  List<ExtendedColor> get extendedColors => [
  ];
}

class ExtendedColor {
  final Color seed, value;
  final ColorFamily light;
  final ColorFamily lightHighContrast;
  final ColorFamily lightMediumContrast;
  final ColorFamily dark;
  final ColorFamily darkHighContrast;
  final ColorFamily darkMediumContrast;

  const ExtendedColor({
    required this.seed,
    required this.value,
    required this.light,
    required this.lightHighContrast,
    required this.lightMediumContrast,
    required this.dark,
    required this.darkHighContrast,
    required this.darkMediumContrast,
  });
}

class ColorFamily {
  const ColorFamily({
    required this.color,
    required this.onColor,
    required this.colorContainer,
    required this.onColorContainer,
  });

  final Color color;
  final Color onColor;
  final Color colorContainer;
  final Color onColorContainer;
}
