enum RoutineTargetMode { targetTime, targetDuration }

/// How today's usable time is bounded, chosen fresh on the Wake screen
/// each time (per spec: not a fixed setting, picked every morning).
///
/// - [targetTime]: routine runs until a specific clock time today
///   (e.g. "everything done by 18:30").
/// - [targetDuration]: routine runs for a fixed total duration from
///   wake time (e.g. "8 hours of routine, whenever that ends").
class RoutineTarget {
  final RoutineTargetMode mode;

  /// Used when mode == targetTime. Hour/minute of the target clock time.
  final int? targetHour;
  final int? targetMinute;

  /// Used when mode == targetDuration.
  final int? targetDurationMinutes;

  const RoutineTarget.time({required int hour, required int minute})
    : mode = RoutineTargetMode.targetTime,
      targetHour = hour,
      targetMinute = minute,
      targetDurationMinutes = null;

  const RoutineTarget.duration({required int minutes})
    : mode = RoutineTargetMode.targetDuration,
      targetDurationMinutes = minutes,
      targetHour = null,
      targetMinute = null;

  /// Total usable minutes from [wakeTime] to the target, per this mode.
  int totalMinutesFrom(DateTime wakeTime) =>
      endFrom(wakeTime).difference(wakeTime).inMinutes;

  /// The instant the routine must finish by, per this mode. A [targetTime]
  /// value not after [wakeTime] resolves to tomorrow (e.g. woke at 20:00
  /// targeting 18:30 means tomorrow 18:30, not the past).
  DateTime endFrom(DateTime wakeTime) {
    if (mode == RoutineTargetMode.targetDuration) {
      return wakeTime.add(Duration(minutes: targetDurationMinutes!));
    }
    var target = DateTime(
      wakeTime.year,
      wakeTime.month,
      wakeTime.day,
      targetHour!,
      targetMinute!,
    );
    // If the target clock time is not after wake time (e.g. woke up
    // at 20:00 targeting 18:30), it must mean tomorrow.
    if (!target.isAfter(wakeTime)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }
}
