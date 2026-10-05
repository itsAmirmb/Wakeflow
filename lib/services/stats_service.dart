import 'dart:math' as math;

import '../models/block.dart';
import '../models/category.dart';
import 'database_service.dart';
import 'day_key.dart';

/// Per-category totals within some set of blocks (one day, or a week).
class CategoryStat {
  final Category category;

  /// Exact active seconds across completed blocks. Minutes are derived
  /// from this aggregate, not per block, so two 59-second blocks count
  /// as one minute together (instead of rounding each down to zero).
  final int completedSeconds;
  final int plannedMinutes;
  final int completedBlocks;
  final int skippedBlocks;

  const CategoryStat({
    required this.category,
    required this.completedSeconds,
    required this.plannedMinutes,
    required this.completedBlocks,
    required this.skippedBlocks,
  });

  int get completedMinutes => completedSeconds ~/ 60;

  /// completedMinutes / plannedMinutes, 0 when nothing was planned.
  double get completionRatio =>
      plannedMinutes == 0 ? 0 : completedMinutes / plannedMinutes;

  CategoryStat operator +(CategoryStat other) => CategoryStat(
    category: category,
    completedSeconds: completedSeconds + other.completedSeconds,
    plannedMinutes: plannedMinutes + other.plannedMinutes,
    completedBlocks: completedBlocks + other.completedBlocks,
    skippedBlocks: skippedBlocks + other.skippedBlocks,
  );
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

  bool get isEmpty =>
      plannedMinutes == 0 && completedBlocks == 0 && skippedBlocks == 0;
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
    return buildDailyStats(day, blocks, categories);
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
      days.add(buildDailyStats(key, blocks, categories));
    }

    // Sum per-category stats across all 7 days.
    final byCategory = <String, CategoryStat>{};
    for (final day in days) {
      for (final stat in day.categoryStats) {
        final existing = byCategory[stat.category.id];
        byCategory[stat.category.id] = existing == null
            ? stat
            : existing + stat;
      }
    }

    final weekCategoryStats = categories
        .map(
          (c) =>
              byCategory[c.id] ??
              CategoryStat(
                category: c,
                completedSeconds: 0,
                plannedMinutes: 0,
                completedBlocks: 0,
                skippedBlocks: 0,
              ),
        )
        .toList();

    return WeeklyStats(days: days, categoryStats: weekCategoryStats);
  }

  DailyStats buildDailyStats(
    String day,
    List<Block> blocks,
    List<Category> categories,
  ) {
    // Blocks of a deleted category still count: rebuild it from the blocks'
    // own id/title so removing a category never erases history.
    final known = {for (final c in categories) c.id};
    final orphans = <String, Category>{};
    for (final block in blocks) {
      if (known.contains(block.categoryId)) continue;
      orphans.putIfAbsent(
        block.categoryId,
        () => Category(
          id: block.categoryId,
          name: block.title,
          icon: '🗂️',
          percentage: 0,
          minimumMinutes: 0,
          preferredBlockMinMinutes: 1,
          preferredBlockMaxMinutes: 60,
          enabled: false,
        ),
      );
    }
    final stats = [...categories, ...orphans.values].map((category) {
      final categoryBlocks = blocks
          .where((b) => b.categoryId == category.id)
          .toList();

      int completedSeconds = 0;
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
          // Exact active seconds (timer data takes precedence over legacy
          // timestamps), aggregated before any minute truncation.
          completedSeconds += math.max(0, block.accumulatedSeconds);
          if (block.accumulatedSeconds == 0 &&
              block.actualStart != null &&
              block.actualEnd != null) {
            completedSeconds += math.max(
              0,
              block.actualEnd!.difference(block.actualStart!).inSeconds,
            );
          }
        } else if (block.status == BlockStatus.partial) {
          // Real work saved by a timer reset: counts as time done, but it is
          // not a completed block.
          completedSeconds += math.max(0, block.accumulatedSeconds);
        } else if (block.status == BlockStatus.skipped) {
          skippedBlocks++;
        }
      }

      return CategoryStat(
        category: category,
        completedSeconds: completedSeconds,
        plannedMinutes: plannedMinutes,
        completedBlocks: completedBlocks,
        skippedBlocks: skippedBlocks,
      );
    }).toList();

    return DailyStats(day: day, categoryStats: stats);
  }
}
