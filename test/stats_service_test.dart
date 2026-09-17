import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/models/category.dart';
import 'package:wakeflow/services/stats_service.dart';

Category category(String id) => Category(
  id: id,
  name: id,
  icon: '',
  percentage: 1,
  minimumMinutes: 0,
  preferredBlockMinMinutes: 1,
  preferredBlockMaxMinutes: 60,
);

Block block({
  required String id,
  required String categoryId,
  required BlockStatus status,
  int planned = 60,
  int elapsedSeconds = 0,
  DateTime? actualStart,
  DateTime? actualEnd,
}) => Block(
  id: id,
  categoryId: categoryId,
  title: id,
  plannedDurationMinutes: planned,
  status: status,
  accumulatedSeconds: elapsedSeconds,
  actualStart: actualStart,
  actualEnd: actualEnd,
);

void main() {
  test('two short completed blocks aggregate into one minute', () {
    final stats = StatsService.instance.buildDailyStats(
      '2026-09-18',
      [
        block(
          id: 'a1',
          categoryId: 'academic',
          status: BlockStatus.completed,
          elapsedSeconds: 59,
        ),
        block(
          id: 'a2',
          categoryId: 'academic',
          status: BlockStatus.completed,
          elapsedSeconds: 59,
        ),
      ],
      [category('academic')],
    );
    expect(stats.completedMinutes, 1);
  });

  test('a single sub-minute block rounds down to zero minutes', () {
    final stats = StatsService.instance.buildDailyStats(
      '2026-09-18',
      [
        block(
          id: 'a1',
          categoryId: 'academic',
          status: BlockStatus.completed,
          elapsedSeconds: 59,
        ),
      ],
      [category('academic')],
    );
    expect(stats.completedMinutes, 0);
  });

  test('timer seconds take precedence over legacy timestamps', () {
    final stats = StatsService.instance.buildDailyStats(
      '2026-09-18',
      [
        block(
          id: 'a1',
          categoryId: 'academic',
          status: BlockStatus.completed,
          elapsedSeconds: 1800,
          actualStart: DateTime(2026, 9, 18, 10),
          actualEnd: DateTime(2026, 9, 18, 19, 30),
        ),
      ],
      [category('academic')],
    );
    expect(stats.completedMinutes, 30);
  });

  test('legacy timestamp fallback works without timer data', () {
    final stats = StatsService.instance.buildDailyStats(
      '2026-09-18',
      [
        block(
          id: 'a1',
          categoryId: 'academic',
          status: BlockStatus.completed,
          actualStart: DateTime(2026, 9, 18, 10, 0),
          actualEnd: DateTime(2026, 9, 18, 10, 45, 30),
        ),
      ],
      [category('academic')],
    );
    expect(stats.completedMinutes, 45);
  });

  test('weekly sums aggregate seconds before truncation', () {
    final stat = CategoryStat(
      category: category('academic'),
      completedSeconds: 59,
      plannedMinutes: 10,
      completedBlocks: 1,
      skippedBlocks: 0,
    );
    final week = stat + stat + stat; // 3 x 59s = 177s -> 2 minutes
    expect(week.completedSeconds, 177);
    expect(week.completedMinutes, 2);
  });

  test('planned minutes exclude cancelled blocks', () {
    final stats = StatsService.instance.buildDailyStats(
      '2026-09-18',
      [
        block(
          id: 'a1',
          categoryId: 'academic',
          status: BlockStatus.completed,
          elapsedSeconds: 600,
        ),
        block(
          id: 'a2',
          categoryId: 'academic',
          status: BlockStatus.cancelled,
          planned: 30,
        ),
      ],
      [category('academic')],
    );
    expect(stats.plannedMinutes, 60);
  });
}
