import '../models/day_mode.dart';

class DayModeCalculator {
  // Hardcoded for now; will move to Settings (user-editable) later.
  static const targetWakeHour = 8;
  static const targetWakeMinute = 0;

  static DayMode calculate(DateTime wakeTime) {
    final target = DateTime(
      wakeTime.year,
      wakeTime.month,
      wakeTime.day,
      targetWakeHour,
      targetWakeMinute,
    );

    final diffMinutes = wakeTime.difference(target).inMinutes;

    if (diffMinutes <= -30) return DayMode.early;
    if (diffMinutes <= 30) return DayMode.normal;
    if (diffMinutes <= 180) return DayMode.late;
    return DayMode.emergency;
  }
}