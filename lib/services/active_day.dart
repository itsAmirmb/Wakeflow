import 'database_service.dart';
import 'day_key.dart';

/// Decides which day's routine is "the current one".
///
/// A day does not end at midnight but at the user's reset time. After that
/// time a new day starts, unless the previous routine still has blocks left
/// to run (pending, active or paused): that routine carries over until it is
/// finished or distilled, so unfinished work is never silently dropped.
class ActiveDay {
  /// Calendar day shifted by the reset time, e.g. with a 04:00 reset,
  /// 01:30 on the 6th still belongs to the 5th.
  static String logicalDayKey(DateTime now, int resetMinutes) =>
      dayKey(now.subtract(Duration(minutes: resetMinutes)));

  static Future<String> resolve(DatabaseService db, DateTime now) async {
    final settings = await db.getSettings();
    final logical = logicalDayKey(now, settings.dayResetMinutes);
    final carried = await db.latestUnfinishedDayBefore(logical);
    return carried ?? logical;
  }
}
