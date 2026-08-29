import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light, dark, or whatever the phone is set to.
///
/// The app shipped with `themeMode: ThemeMode.light` hard-coded, which made
/// the whole `MaterialTheme.darkScheme()` in theme.dart dead code — a full
/// dark palette that nothing could ever reach. It could not simply be switched
/// on, either: around ninety `Colors.grey` / `Colors.black54` / `Colors.red`
/// literals were scattered through the screens, and every one of them would
/// have gone unreadable. Those are gone now, so the switch is worth having.
///
/// Held in a [ValueNotifier] rather than passed down: the only thing that
/// listens is the [MaterialApp] itself, and the only thing that writes is one
/// row in App Settings.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  static const _key = 'themeMode';

  /// Reads the stored choice. Failure is not worth surfacing — the app simply
  /// follows the system, which is what it would have done anyway.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      value = ThemeMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      // Keep the default.
    }
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == value) return;
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // The theme still changed for this run; it just will not be remembered.
    }
  }
}

/// The app's single instance.
final themeController = ThemeController();

extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
        ThemeMode.system => 'Follow system',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  IconData get icon => switch (this) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };
}
