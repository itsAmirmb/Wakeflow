import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/app_settings.dart';
import 'package:wakeflow/screens/settings_screen.dart';

void main() {
  testWidgets(
    'add sorts and deduplicates times; remove persists without scheduling',
    (tester) async {
      var saved = const AppSettings(checkpointMinutesOfDay: [900]);
      var schedules = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(
              loadCategories: () async => [],
              loadSettings: () async => saved,
              persistSettings: (value) async => saved = value,
              scheduleWakeReminder: (_, _) async => schedules++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Schedule updates when you open Today'),
        findsOneWidget,
      );
      Future<void> addNoon() async {
        await tester.tap(find.byTooltip('Add checkpoint time'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.keyboard_outlined));
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '12');
        await tester.enterText(fields.at(1), '00');
        await tester.tap(find.text('PM'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      await addNoon();
      expect(saved.checkpointMinutesOfDay, [720, 900]);
      await addNoon();
      expect(saved.checkpointMinutesOfDay, [720, 900]);
      await tester.ensureVisible(
        find.byKey(const ValueKey('remove-checkpoint-720')),
      );
      await tester.tap(find.byKey(const ValueKey('remove-checkpoint-720')));
      await tester.pumpAndSettle();
      expect(saved.checkpointMinutesOfDay, [900]);
      expect(schedules, 0);
    },
  );

  testWidgets(
    'failed checkpoint save keeps previous time and reports persistence error',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(
              loadCategories: () async => [],
              loadSettings: () async =>
                  const AppSettings(checkpointMinutesOfDay: [720]),
              persistSettings: (_) async => throw StateError('disk full'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final remove = find.byKey(const ValueKey('remove-checkpoint-720'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(remove, findsOneWidget);
      expect(
        find.text('Could not save settings. Please try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
