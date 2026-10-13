import '../models/day_mode.dart';

class DayModeCalculator {
  /// Used only when no wake time is passed in (08:00).
  static const defaultTargetMinutes = 8 * 60;

  /// [targetMinutes] is the user's target wake time, in minutes after
  /// midnight (the "Wake reminder" setting).
  static DayMode calculate(
    DateTime wakeTime, {
    int targetMinutes = defaultTargetMinutes,
  }) {
    final target = DateTime(
      wakeTime.year,
      wakeTime.month,
      wakeTime.day,
      targetMinutes ~/ 60,
      targetMinutes % 60,
    );

    final diffMinutes = wakeTime.difference(target).inMinutes;

    if (diffMinutes <= -30) return DayMode.early;
    if (diffMinutes <= 30) return DayMode.normal;
    if (diffMinutes <= 180) return DayMode.late;
    return DayMode.emergency;
  }
}