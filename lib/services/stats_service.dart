import '../models/block.dart';
import '../models/category.dart';
import 'database_service.dart';
import 'day_key.dart';

/// Per-category totals within some set of blocks (one day, or a week).
class CategoryStat {
  final Category category;
  final int completedMinutes;
  final int plannedMinutes;
  final int completedBlocks;
  final int skippedBlocks;

  const CategoryStat({
    required this.category,
    required this.completedMinutes,
    required this.plannedMinutes,
    required this.completedBlocks,
    required this.skippedBlocks,
  });

  /// completedMinutes / plannedMinutes, 0 when nothing was planned.
  double get completionRatio =>
      plannedMinutes == 0 ? 0 : completedMinutes / plannedMinutes;
}

class DailyStats {
  final String day;
  final List<CategoryStat> categoryStats;

  const DailyStats({required this.day, required this.categoryStats});

  int get completedMinutes =>
      categoryStats.fold(0, (sum, c) => sum + c.completedMinutes);
  int get plannedMinutes =>
      categoryStats.fold(0, (sum, c) => sum + c.plannedMinutes);
  int get completedBlocks =>
      categoryStats.fold(0, (sum, c) => sum + c.completedBlocks);
  int get skippedBlocks =>
      categoryStats.fold(0, (sum, c) => sum + c.skippedBlocks);

  bool get isEmpty => plannedMinutes == 0 && completedBlocks == 0 && skippedBlocks == 0;
}

class WeeklyStats {
  final List<DailyStats> days; // oldest first, up to 7 entries
  final List<CategoryStat> categoryStats; // summed across the whole week

  const WeeklyStats({required this.days, required this.categoryStats});

  int get completedMinutes =>
      categoryStats.fold(0, (sum, c) => sum + c.completedMinutes);
  int get plannedMinutes =>
      categoryStats.fold(0, (sum, c) => sum + c.plannedMinutes);

  double get completionRatio =>
      plannedMinutes == 0 ? 0 : completedMinutes / plannedMinutes;
}

/// Computes [DailyStats]/[WeeklyStats] from blocks already stored by
/// [DatabaseService]. No new tables — blocks already carry everything
/// needed (status, plannedDurationMinutes, categoryId, elapsedAt).
class StatsService {
  StatsService._internal();
  static final StatsService instance = StatsService._internal();

  Future<DailyStats> getDailyStats(String day) async {
    final blocks = await DatabaseService.instance.getBlocksForDay(day);
    final categories = await DatabaseService.instance.getCategories();
    return _buildDailyStats(day, blocks, categories);
  }

  /// Last 7 days including [today] (yyyy-MM-dd), oldest first.
  Future<WeeklyStats> getWeeklyStats({DateTime? today}) async {
    final now = today ?? DateTime.now();
    final categories = await DatabaseService.instance.getCategories();

    final days = <DailyStats>[];
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final key = dayKey(date);
      final blocks = await DatabaseService.instance.getBlocksForDay(key);
      days.add(_buildDailyStats(key, blocks, categories));
    }

    // Sum per-category stats across all 7 days.
    final byCategory = <String, CategoryStat>{};
    for (final day in days) {
      for (final stat in day.categoryStats) {
        final existing = byCategory[stat.category.id];
        byCategory[stat.category.id] = CategoryStat(
          category: stat.category,
          completedMinutes:
              (existing?.completedMinutes ?? 0) + stat.completedMinutes,
          plannedMinutes: (existing?.plannedMinutes ?? 0) + stat.plannedMinutes,
          completedBlocks:
              (existing?.completedBlocks ?? 0) + stat.completedBlocks,
          skippedBlocks: (existing?.skippedBlocks ?? 0) + stat.skippedBlocks,
        );
      }
    }

    final weekCategoryStats = categories
        .map((c) => byCategory[c.id] ??
            CategoryStat(
              category: c,
              completedMinutes: 0,
              plannedMinutes: 0,
              completedBlocks: 0,
              skippedBlocks: 0,
            ))
        .toList();

    return WeeklyStats(days: days, categoryStats: weekCategoryStats);
  }

  DailyStats _buildDailyStats(
    String day,
    List<Block> blocks,
    List<Category> categories,
  ) {
    final stats = categories.map((category) {
      final categoryBlocks =
          blocks.where((b) => b.categoryId == category.id).toList();

      int completedMinutes = 0;
      int plannedMinutes = 0;
      int completedBlocks = 0;
      int skippedBlocks = 0;

      for (final block in categoryBlocks) {
        // Every generated block (pending/active/completed/skipped) counts
        // toward "planned" — cancelled ones don't, they were removed by
        // a recalculation and were never really part of the day.
        if (block.status != BlockStatus.cancelled) {
          plannedMinutes += block.plannedDurationMinutes;
        }
        if (block.status == BlockStatus.completed) {
          completedBlocks++;
          // Actual time spent, not planned — reflects real effort even
          // if the block ran short or long.
          final actualMinutes = block.elapsedAt(DateTime.now()).inMinutes;
          completedMinutes += actualMinutes;
        } else if (block.status == BlockStatus.skipped) {
          skippedBlocks++;
        }
      }

      return CategoryStat(
        category: category,
        completedMinutes: completedMinutes,
        plannedMinutes: plannedMinutes,
        completedBlocks: completedBlocks,
        skippedBlocks: skippedBlocks,
      );
    }).toList();

    return DailyStats(day: day, categoryStats: stats);
  }
}
