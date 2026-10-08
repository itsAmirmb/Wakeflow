import 'active_day.dart';
import 'database_service.dart';

/// What "ticked off" means right now: the current day (it follows the
/// day-reset time, like the rest of the app) and whether ticks outlive it.
typedef NoteContext = ({String today, bool keepAcrossDays});

Future<NoteContext> loadNoteContext(
  DatabaseService db, {
  DateTime? now,
}) async {
  final settings = await db.getSettings();
  return (
    today: ActiveDay.logicalDayKey(
      now ?? DateTime.now(),
      settings.dayResetMinutes,
    ),
    keepAcrossDays: settings.keepNoteTicksAcrossDays,
  );
}
