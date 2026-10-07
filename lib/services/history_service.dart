import '../models/block.dart';
import '../models/day_mode.dart';
import 'database_service.dart';
import 'stats_service.dart';

/// One past (or current) day as shown in History.
class HistoryDay {
  final String day;
  final DayMode? dayMode;
  final DateTime? wakeTime;
  final List<Block> blocks;
  final DailyStats stats;

  const HistoryDay({
    required this.day,
    required this.dayMode,
    required this.wakeTime,
    required this.blocks,
    required this.stats,
  });

  int _count(bool Function(BlockStatus) test) =>
      blocks.where((b) => test(b.status)).length;

  int get doneBlocks => _count((s) => s == BlockStatus.completed);
  int get partialBlocks => _count((s) => s == BlockStatus.partial);
  int get skippedBlocks => _count((s) => s == BlockStatus.skipped);

  /// Planned but never finished (pending, or left running/paused).
  int get unfinishedBlocks => _count(
    (s) =>
        s == BlockStatus.pending ||
        s == BlockStatus.active ||
        s == BlockStatus.paused,
  );
}

/// Reads past days from the blocks already stored by [DatabaseService]; no
/// extra tables, so history exists for every routine ever generated.
class HistoryService {
  const HistoryService._();

  static const int pageSize = 30;

  static Future<List<HistoryDay>> loadPage({
    int offset = 0,
    int limit = pageSize,
    DatabaseService? database,
  }) async {
    final db = database ?? DatabaseService.instance;
    final days = await db.getBlockDaysPage(limit: limit, offset: offset);
    if (days.isEmpty) return const [];
    final blocksByDay = await db.getBlocksForDays(days);
    final categories = await db.getCategories();
    final result = <HistoryDay>[];
    for (final day in days) {
      final blocks = blocksByDay[day] ?? const <Block>[];
      final meta = await db.getDayMeta(day);
      result.add(
        HistoryDay(
          day: day,
          dayMode: meta?.$1,
          wakeTime: meta?.$2,
          blocks: blocks,
          stats: StatsService.instance.buildDailyStats(day, blocks, categories),
        ),
      );
    }
    return result;
  }
}
