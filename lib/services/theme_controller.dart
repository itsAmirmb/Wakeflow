import 'package:flutter/material.dart';

/// Single source of truth for the app's theme mode. Settings screen
/// updates this (and persists the choice to the DB); MaterialApp
/// listens to it so a change applies instantly, no restart needed.
class ThemeController {
  ThemeController._internal();
  static final ThemeController instance = ThemeController._internal();

  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  void setFromStored(String stored) {
    mode.value = _parse(stored);
  }

  static ThemeMode _parse(String stored) {
    switch (stored) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String toStored(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
