/// Decides whether a checkpoint review is owed right now.
///
/// A checkpoint is due when a configured time of day between wake time and the
/// deadline has passed and no review was saved at or after it. It is derived
/// from saved data (not from a notification), so it still applies after the
/// app was closed, the notification was dismissed, or the phone restarted.
class CheckpointGate {
  static DateTime? dueAt({
    required List<int> minutesOfDay,
    required DateTime wake,
    required DateTime dayEnd,
    required DateTime now,
    required DateTime? lastReviewAt,
  }) {
    if (minutesOfDay.isEmpty) return null;
    final limit = now.isBefore(dayEnd) ? now : dayEnd;
    DateTime? latest;
    var date = DateTime(wake.year, wake.month, wake.day);
    while (!date.isAfter(limit)) {
      for (final minute in minutesOfDay) {
        final when = DateTime(
          date.year,
          date.month,
          date.day,
          minute ~/ 60,
          minute % 60,
        );
        if (!when.isBefore(wake) && !when.isAfter(now) && when.isBefore(dayEnd)) {
          if (latest == null || when.isAfter(latest)) latest = when;
        }
      }
      date = DateTime(date.year, date.month, date.day + 1);
    }
    if (latest == null) return null;
    if (lastReviewAt != null && !lastReviewAt.isBefore(latest)) return null;
    return latest;
  }
}
