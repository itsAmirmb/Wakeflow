import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/routine_target.dart';

void main() {
  group('RoutineTarget.endFrom', () {
    test('targetTime earlier than wake resolves to tomorrow', () {
      // Woke at 20:00 targeting 18:30 — the next 18:30 is tomorrow.
      const target = RoutineTarget.time(hour: 18, minute: 30);
      final end = target.endFrom(DateTime(2026, 9, 17, 20, 0));
      expect(end, DateTime(2026, 9, 18, 18, 30));
    });

    test('targetTime later today resolves to today', () {
      const target = RoutineTarget.time(hour: 18, minute: 30);
      final end = target.endFrom(DateTime(2026, 9, 17, 10, 0));
      expect(end, DateTime(2026, 9, 17, 18, 30));
    });

    test('targetTime equal to wake time resolves to tomorrow', () {
      const target = RoutineTarget.time(hour: 20, minute: 0);
      final end = target.endFrom(DateTime(2026, 9, 17, 20, 0));
      expect(end, DateTime(2026, 9, 18, 20, 0));
    });

    test('targetDuration ends exactly that many minutes after wake', () {
      const target = RoutineTarget.duration(minutes: 8 * 60);
      final end = target.endFrom(DateTime(2026, 9, 17, 10, 15));
      expect(end, DateTime(2026, 9, 17, 18, 15));
    });

    test('totalMinutesFrom stays consistent with endFrom', () {
      const timeTarget = RoutineTarget.time(hour: 18, minute: 30);
      const durationTarget = RoutineTarget.duration(minutes: 300);
      final wake = DateTime(2026, 9, 17, 12, 0);
      expect(timeTarget.totalMinutesFrom(wake), 390);
      expect(durationTarget.totalMinutesFrom(wake), 300);
    });

    test('duration target may legitimately cross midnight', () {
      const target = RoutineTarget.duration(minutes: 120);
      final end = target.endFrom(DateTime(2026, 9, 17, 23, 0));
      expect(end, DateTime(2026, 9, 18, 1, 0));
    });
  });
}
