import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/services/routine_engine.dart';
import 'package:wakeflow/data/default_categories.dart';

void main() {
  test('completed blocks are untouched after checkpoint recalculation', () {
    final now = DateTime(2026, 1, 1, 12, 30);
    final dayEnd = DateTime(2026, 1, 2);

    final completedBlock = Block(
      id: 'block_0',
      categoryId: 'academic',
      title: 'Academic',
      plannedDurationMinutes: 90,
      plannedStart: DateTime(2026, 1, 1, 10, 0),
      plannedEnd: DateTime(2026, 1, 1, 11, 30),
      status: BlockStatus.completed,
    );
    final pendingBlock = Block(
      id: 'block_1',
      categoryId: 'trading',
      title: 'Trading',
      plannedDurationMinutes: 60,
      plannedStart: DateTime(2026, 1, 1, 11, 40),
      plannedEnd: DateTime(2026, 1, 1, 12, 40),
      status: BlockStatus.pending,
    );

    final result = RoutineEngine.recalculateFromCheckpoint(
      currentBlocks: [completedBlock, pendingBlock],
      categories: defaultCategories,
      now: now,
      dayEnd: dayEnd,
      bufferMinutes: 10,
    );

    // The completed block must be byte-for-byte unchanged.
    expect(result.first.status, BlockStatus.completed);
    expect(result.first.plannedStart, completedBlock.plannedStart);
    expect(result.first.plannedEnd, completedBlock.plannedEnd);

    // New future blocks should start at or after `now`.
    final futureBlocks = result.where((b) => b.status == BlockStatus.pending);
    for (final b in futureBlocks) {
      expect(b.plannedStart!.isAfter(now) || b.plannedStart!.isAtSameMomentAs(now), true);
    }
  });
}