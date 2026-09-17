import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/models/category.dart';
import 'package:wakeflow/models/checkpoint_report.dart';

void main() {
  final now = DateTime(2099, 1, 10, 12);
  final dayEnd = DateTime(2099, 1, 10, 20);
  const work = Category(
    id: 'work',
    name: 'Work',
    icon: '💼',
    percentage: 1,
    minimumMinutes: 0,
    preferredBlockMinMinutes: 15,
    preferredBlockMaxMinutes: 60,
    priority: 0,
  );
  const rest = Category(
    id: 'rest',
    name: 'Rest',
    icon: '☕',
    percentage: 1,
    minimumMinutes: 0,
    preferredBlockMinMinutes: 15,
    preferredBlockMaxMinutes: 60,
    priority: 1,
  );

  Block block(
    String id, {
    BlockStatus status = BlockStatus.pending,
    int minutes = 60,
    DateTime? plannedStart,
    DateTime? plannedEnd,
    DateTime? actualStart,
    DateTime? actualEnd,
    int accumulatedSeconds = 0,
    DateTime? runningSince,
  }) => Block(
    id: id,
    categoryId: id.startsWith('orphan') ? 'gone' : id.split('-').first,
    title: id,
    plannedDurationMinutes: minutes,
    plannedStart: plannedStart,
    plannedEnd: plannedEnd,
    actualStart: actualStart,
    actualEnd: actualEnd,
    status: status,
    accumulatedSeconds: accumulatedSeconds,
    runningSince: runningSince,
  );

  CategoryProgress progressOf(CheckpointReport report, String id) =>
      report.categories.singleWhere((progress) => progress.category.id == id);

  test('evening block is not due in a morning report', () {
    final report = CheckpointReport.fromBlocks(
      blocks: [
        block('work-1', plannedStart: DateTime(2099, 1, 10, 18), minutes: 60),
      ],
      categories: const [work],
      now: now,
      dayEnd: dayEnd,
    );
    final progress = progressOf(report, 'work');
    expect(progress.expectedSeconds, 0);
    expect(progress.actualSeconds, 0);
    expect(progress.targetSeconds, 3600);
  });

  test('partial timer work counts alongside accumulated and running time', () {
    final report = CheckpointReport.fromBlocks(
      blocks: [
        block(
          'work-1',
          status: BlockStatus.active,
          minutes: 60,
          plannedStart: DateTime(2099, 1, 10, 11),
          plannedEnd: DateTime(2099, 1, 10, 12),
          actualStart: DateTime(2099, 1, 10, 11, 30),
          accumulatedSeconds: 600,
          runningSince: DateTime(2099, 1, 10, 11, 59),
        ),
        block(
          'rest-1',
          status: BlockStatus.skipped,
          minutes: 30,
          plannedStart: DateTime(2099, 1, 10, 9),
          actualStart: DateTime(2099, 1, 10, 9),
          accumulatedSeconds: 0,
          actualEnd: DateTime(2099, 1, 10, 9, 10),
        ),
      ],
      categories: const [work, rest],
      now: now,
      dayEnd: dayEnd,
    );
    final workProgress = progressOf(report, 'work');
    // 10 banked minutes plus the one minute from 11:59 to 12:00.
    // Expected is the full scheduled hour, independent of actualStart.
    expect(workProgress.actualSeconds, 600 + 60);
    expect(workProgress.expectedSeconds, 3600);
    // A skipped block still contributes whatever work actually happened.
    final restProgress = progressOf(report, 'rest');
    expect(restProgress.actualSeconds, 600);
    expect(restProgress.expectedSeconds, 1800);
  });

  test('aggregate seconds round down to minutes: 59+59 becomes 1 minute', () {
    final report = CheckpointReport.fromBlocks(
      blocks: [
        block(
          'work-1',
          status: BlockStatus.completed,
          minutes: 1,
          actualStart: DateTime(2099, 1, 10, 11),
          accumulatedSeconds: 59,
        ),
        block(
          'work-2',
          status: BlockStatus.completed,
          minutes: 1,
          actualStart: DateTime(2099, 1, 10, 12),
          accumulatedSeconds: 59,
        ),
      ],
      categories: const [work],
      now: now,
      dayEnd: dayEnd,
    );
    final progress = progressOf(report, 'work');
    expect(progress.actualSeconds, 118);
    expect(progress.doneMinutes, 1);
    // Each completed block starts exactly at the report's now, so the
    // plan before "now" covers neither: expected work is still 0.
    expect(progress.expectedSeconds, 0);
    expect(progress.expectedMinutes, 0);
  });

  test('paused work excludes the pause and negative inputs are clamped', () {
    final report = CheckpointReport.fromBlocks(
      blocks: [
        block(
          'work-1',
          status: BlockStatus.paused,
          minutes: 60,
          actualStart: DateTime(2099, 1, 10, 11),
          accumulatedSeconds: 900,
          runningSince: DateTime(2099, 1, 10, 12),
        ),
        block(
          'work-2',
          status: BlockStatus.completed,
          minutes: 0,
          accumulatedSeconds: -5,
        ),
      ],
      categories: const [work],
      now: now,
      dayEnd: dayEnd,
    );
    final progress = progressOf(report, 'work');
    // Paused keeps only banked seconds; a paused row's runningSince must not
    // silently add time, and negative junk cannot subtract.
    expect(progress.actualSeconds, 900);
    expect(progress.targetSeconds, 3600);
    expect(progress.expectedSeconds, 0);
  });

  test('expected progress stops at an expired deadline', () {
    final report = CheckpointReport.fromBlocks(
      blocks: [
        block(
          'work-1',
          status: BlockStatus.pending,
          minutes: 60,
          plannedStart: DateTime(2099, 1, 10, 19),
        ),
      ],
      categories: const [work],
      now: DateTime(2099, 1, 10, 21),
      dayEnd: dayEnd,
    );
    final progress = progressOf(report, 'work');
    // After the deadline nothing remains, and "scheduled till now" stops
    // at the block's own planned end (20:00) instead of tracking the
    // late report time (21:00): exactly the full scheduled hour.
    expect(progress.expectedSeconds, 3600);
    expect(report.remainingMinutes, 0);
  });

  test('removed categories keep their evidence in the report', () {
    final report = CheckpointReport.fromBlocks(
      blocks: [
        block(
          'orphan-1',
          status: BlockStatus.completed,
          minutes: 30,
          accumulatedSeconds: 1800,
        ),
      ],
      categories: const [work],
      now: now,
      dayEnd: dayEnd,
    );
    final orphan = report.categories.singleWhere(
      (progress) => progress.category.id == 'gone',
    );
    expect(orphan.actualSeconds, 1800);
    expect(orphan.category.name, 'orphan-1');
  });

  test('JSON snapshot records times and per-category seconds', () {
    final report = CheckpointReport.fromBlocks(
      blocks: [
        block(
          'work-1',
          status: BlockStatus.active,
          minutes: 60,
          plannedStart: DateTime(2099, 1, 10, 11),
          actualStart: DateTime(2099, 1, 10, 11, 30),
          runningSince: DateTime(2099, 1, 10, 11, 50),
        ),
      ],
      categories: const [work],
      now: now,
      dayEnd: dayEnd,
    );
    final json = report.toJson();
    expect(json['now'], now.toIso8601String());
    expect(json['dayEnd'], dayEnd.toIso8601String());
    final categories = json['categories']! as List<Object?>;
    final workJson = categories.single as Map<String, Object?>;
    expect(workJson['id'], 'work');
    expect(workJson['targetSeconds'], 3600);
    expect(workJson['expectedSeconds'], 3600);
    // Only the live running stretch (11:50-12:00) is banked: with no
    // accumulatedSeconds the 11:30 actualStart is not retroactive time.
    expect(workJson['actualSeconds'], 600);
  });
}
