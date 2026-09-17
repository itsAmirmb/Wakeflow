import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/app_settings.dart';
import 'package:wakeflow/screens/settings_screen.dart';
import 'package:wakeflow/screens/wake_screen.dart';
import 'package:wakeflow/services/theme_controller.dart';

void main() {
  tearDown(() => ThemeController.instance.mode.value = ThemeMode.system);

  test('only hour/minute changes require wake rescheduling', () {
    const settings = AppSettings();
    expect(
      SettingsScreen.wakeTimeChanged(
        settings,
        settings.copyWith(themeMode: 'dark'),
      ),
      isFalse,
    );
    expect(
      SettingsScreen.wakeTimeChanged(
        settings,
        settings.copyWith(bufferMinutes: 20),
      ),
      isFalse,
    );
    expect(
      SettingsScreen.wakeTimeChanged(
        settings,
        settings.copyWith(wakeReminderHour: 9),
      ),
      isTrue,
    );
    expect(
      SettingsScreen.wakeTimeChanged(
        settings,
        settings.copyWith(wakeReminderMinute: 1),
      ),
      isTrue,
    );
    expect(SettingsScreen.wakeTimeChanged(settings, settings), isFalse);
  });

  testWidgets('theme save persists without notification scheduling', (
    tester,
  ) async {
    var schedules = 0;
    AppSettings? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            loadCategories: () async => [],
            loadSettings: () async => const AppSettings(),
            persistSettings: (value) async => saved = value,
            scheduleWakeReminder: (_, _) async => schedules++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(saved?.themeMode, 'dark');
    expect(schedules, 0);
  });

  testWidgets('failed theme save rolls back theme and reports error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            loadCategories: () async => [],
            loadSettings: () async => const AppSettings(),
            persistSettings: (_) async => throw StateError('disk full'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(ThemeController.instance.mode.value, ThemeMode.system);
    expect(
      find.text('Could not save settings. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('save completion after disposal does not setState', (
    tester,
  ) async {
    final saved = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            loadCategories: () async => [],
            loadSettings: () async => const AppSettings(),
            persistSettings: (_) => saved.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    saved.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('load failure offers retry instead of indefinite spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            loadCategories: () async => throw StateError('unavailable'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Later waits for actual scheduling and disables duplicate taps', (
    tester,
  ) async {
    final scheduled = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WakeScreen(
          scheduleSnooze: () {
            calls++;
            return scheduled.future;
          },
        ),
      ),
    );
    await tester.tap(find.text('30 MIN LATER'));
    await tester.pump();
    await tester.tap(find.text('30 MIN LATER'));
    expect(calls, 1);
    expect(find.textContaining('Reminder scheduled'), findsNothing);
    scheduled.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Reminder scheduled'), findsOneWidget);
  });

  testWidgets('Later failure does not claim reminder was set', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WakeScreen(
          scheduleSnooze: () async => throw StateError('denied'),
        ),
      ),
    );
    await tester.tap(find.text('30 MIN LATER'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not schedule reminder'), findsOneWidget);
    expect(find.textContaining('Reminder scheduled'), findsNothing);
  });
}
