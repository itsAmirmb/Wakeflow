import 'dart:async';

import 'package:flutter/material.dart';

import 'models/app_settings.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';
import 'services/theme_controller.dart';

Future<void> main() async {
  // Required before any plugin (sqflite, notifications) is used prior to runApp.
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const WakeFlowApp());
  // Render before plugins/permissions. All asynchronous bootstrap errors are
  // handled below; a denied permission never prevents runApp.
  unawaited(_loadSettingsAndApply());
}

Future<void> _loadSettingsAndApply() async {
  var settings = const AppSettings();
  try {
    settings = await DatabaseService.instance.getSettings();
  } on Object catch (error) {
    debugPrint('Settings load failed, using defaults: $error');
  }

  ThemeController.instance.setFromStored(settings.themeMode);
  try {
    await NotificationService.instance.requestPermissions();
  } catch (error) {
    debugPrint('Notification permission request failed: $error');
  }
  try {
    await NotificationService.instance.scheduleWakeReminder(
      hour: settings.wakeReminderHour,
      minute: settings.wakeReminderMinute,
    );
  } catch (error) {
    debugPrint('Wake reminder scheduling failed (app continues): $error');
  }
}

class WakeFlowApp extends StatelessWidget {
  const WakeFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'WakeFlow',
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: themeMode,
          home: const HomeScreen(),
        );
      },
    );
  }

  /// One theme builder for both brightnesses, so light/dark never drift
  /// apart accidentally — everything (cards, buttons, nav bar, text)
  /// derives from the same seed color and shape rules.
  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        elevation: 0,
        indicatorColor: colorScheme.secondaryContainer,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        // Rounded progress bars read as more polished than the sharp
        // Material default.
        borderRadius: BorderRadius.circular(8),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: const FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
