import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/models/category.dart';
import 'package:wakeflow/services/routine_engine.dart';

Category category(String id, {int minimum = 0, int maximum = 1000}) => Category(
  id: id,
  name: id,
  icon: '',
  percentage: 1,
  minimumMinutes: minimum,
  preferredBlockMinMinutes: 1,
  preferredBlockMaxMinutes: maximum,
);

void main() {
  final now = DateTime(2026, 1, 1, 12, 30);

  Block block(
    String id,
    BlockStatus status, {
    String categoryId = 'a',
    int planned = 60,
    int elapsedSeconds = 0,
    DateTime? runningSince,
    DateTime? actualStart,
    DateTime? actualEnd,
    DateTime? plannedEnd,
  }) => Block(
    id: id,
    categoryId: categoryId,
    title: id,
    plannedDurationMinutes: planned,
    status: status,
    accumulatedSeconds: elapsedSeconds,
    runningSince: runningSince,
    actualStart: actualStart,
    actualEnd: actualEnd,
    plannedStart: now.subtract(const Duration(hours: 2)),
    plannedEnd: plannedEnd ?? now.subtract(const Duration(hours: 1)),
  );

  List<Block> recalculate(
    List<Block> blocks, {
    List<Category>? categories,
    int remaining = 120,
    int gap = 0,
  }) => RoutineEngine.recalculateFromCheckpoint(
    currentBlocks: blocks,
    categories: categories ?? [category('a'), category('b')],
    now: now,
    dayEnd: now.add(Duration(minutes: remaining)),
    bufferMinutes: gap,
  );

  Map<String, int> futureTotals(List<Block> blocks) {
    final totals = <String, int>{};
    for (final b in blocks.where((b) => b.status == BlockStatus.pending)) {
      totals.update(
        b.categoryId,
        (v) => v + b.plannedDurationMinutes,
        ifAbsent: () => b.plannedDurationMinutes,
      );
    }
    return totals;
  }

  void expectFutureFits(
    List<Block> blocks,
    DateTime earliest,
    DateTime end,
    int gap,
  ) {
    final future = blocks
        .where((b) => b.status == BlockStatus.pending)
        .toList();
    for (var i = 0; i < future.length; i++) {
      expect(future[i].plannedStart!.isBefore(earliest), isFalse);
      expect(future[i].plannedEnd!.isAfter(end), isFalse);
      if (i > 0) {
        expect(
          future[i].plannedStart!
              .difference(future[i - 1].plannedEnd!)
              .inMinutes,
          gap,
        );
      }
    }
    expect(blocks.map((b) => b.id).toSet().length, blocks.length);
  }

  test(
    'every nonpending object and ID is preserved; pending blocks replaced',
    () {
      final preserved = [
        block('completed', BlockStatus.completed, elapsedSeconds: 1200),
        block('active', BlockStatus.active, elapsedSeconds: 1800),
        block('paused', BlockStatus.paused, elapsedSeconds: 2700),
        block('skipped', BlockStatus.skipped),
        block('cancelled', BlockStatus.cancelled),
      ];
      final oldPending = block('old-pending', BlockStatus.pending);
      final result = recalculate(
        [preserved[0], oldPending, ...preserved.skip(1)],
        remaining: 300,
        gap: 10,
      );
      for (var i = 0; i < preserved.length; i++) {
        expect(identical(result[i], preserved[i]), isTrue);
        expect(result[i].id, preserved[i].id);
      }
      expect(result.any((b) => b.id == oldPending.id), isFalse);
      expectFutureFits(
        result,
        now.add(const Duration(minutes: 65)),
        now.add(const Duration(minutes: 300)),
        10,
      );
    },
  );

  test('stale planned history never moves the future before now', () {
    final completed = block('old', BlockStatus.completed);
    final result = recalculate([completed]);
    expect(result[1].plannedStart, now);
    expectFutureFits(result, now, now.add(const Duration(minutes: 120)), 0);
  });

  test(
    'skipped and cancelled future planned ends neither delay nor credit work',
    () {
      final result = recalculate([
        block(
          'skip',
          BlockStatus.skipped,
          elapsedSeconds: 3600,
          plannedEnd: now.add(const Duration(hours: 4)),
        ),
        block(
          'cancel',
          BlockStatus.cancelled,
          elapsedSeconds: 3600,
          plannedEnd: now.add(const Duration(hours: 8)),
        ),
      ]);
      expect(result[2].plannedStart, now);
      expect(futureTotals(result), {'a': 60, 'b': 60});
    },
  );

  test(
    'completed actual minutes, not planned minutes, credit daily weights',
    () {
      final result = recalculate([
        block(
          'done',
          BlockStatus.completed,
          planned: 120,
          elapsedSeconds: 60 * 60,
        ),
      ]);
      // 60 completed + 120 future = 180 daily minutes: 90 per category.
      expect(futureTotals(result), {'a': 30, 'b': 90});
    },
  );

  test(
    'actual credit satisfies minimums instead of applying full minima again',
    () {
      final result = recalculate(
        [block('done', BlockStatus.completed, elapsedSeconds: 60 * 60)],
        categories: [category('a', minimum: 60), category('b', minimum: 60)],
        remaining: 60,
      );
      expect(futureTotals(result), {'b': 60});
    },
  );

  test(
    'over-completed category gets no more until other category catches up',
    () {
      final result = recalculate([
        block('done', BlockStatus.completed, elapsedSeconds: 300 * 60),
      ], remaining: 60);
      expect(futureTotals(result), {'b': 60});
    },
  );

  test('emergency compression applies to unmet daily minimums only', () {
    final result = recalculate(
      [block('done', BlockStatus.completed, elapsedSeconds: 60 * 60)],
      categories: [category('a', minimum: 90), category('b', minimum: 60)],
      remaining: 30,
    );
    expect(futureTotals(result), {'a': 10, 'b': 20});
  });

  test(
    'completed timer data excludes pauses and takes precedence over timestamps',
    () {
      final result = recalculate([
        block(
          'done',
          BlockStatus.completed,
          elapsedSeconds: 30 * 60,
          actualStart: now.subtract(const Duration(hours: 3)),
          actualEnd: now,
        ),
      ]);
      expect(futureTotals(result), {'a': 45, 'b': 75});
    },
  );

  test(
    'legacy completion timestamps provide actual credit, absent data does not',
    () {
      final legacy = recalculate([
        block(
          'done',
          BlockStatus.completed,
          actualStart: now.subtract(const Duration(minutes: 60)),
          actualEnd: now,
        ),
      ]);
      expect(futureTotals(legacy), {'a': 30, 'b': 90});
      final missing = recalculate([
        block('done', BlockStatus.completed, planned: 300),
      ]);
      expect(futureTotals(missing), {'a': 60, 'b': 60});
    },
  );

  test('subminute completed durations aggregate before minute truncation', () {
    final result = recalculate([
      block('one', BlockStatus.completed, elapsedSeconds: 40),
      block('two', BlockStatus.completed, elapsedSeconds: 40),
      block('three', BlockStatus.completed, elapsedSeconds: 40),
    ], remaining: 2);
    expect(futureTotals(result), {'b': 2});
  });

  test(
    'active remaining commitment includes accumulated and running seconds',
    () {
      final active = block(
        'active',
        BlockStatus.active,
        elapsedSeconds: 10 * 60,
        runningSince: now.subtract(const Duration(minutes: 20)),
      );
      final result = recalculate([active]);
      expect(identical(result.first, active), isTrue);
      expect(result[1].plannedStart, now.add(const Duration(minutes: 30)));
      // 60 committed + 90 free = 150 daily minutes, 75 each.
      expect(futureTotals(result), {'a': 15, 'b': 75});
      expectFutureFits(
        result,
        now.add(const Duration(minutes: 30)),
        now.add(const Duration(minutes: 120)),
        0,
      );
    },
  );

  test('active commitment is credited against minima with a boundary gap', () {
    final result = recalculate(
      [block('active', BlockStatus.active, elapsedSeconds: 30 * 60)],
      categories: [category('a', minimum: 60), category('b', minimum: 60)],
      remaining: 100,
      gap: 10,
    );
    expect(result[1].plannedStart, now.add(const Duration(minutes: 40)));
    expect(futureTotals(result), {'b': 60});
    expectFutureFits(
      result,
      now.add(const Duration(minutes: 40)),
      now.add(const Duration(minutes: 100)),
      10,
    );
  });

  test(
    'paused work reserves remaining time regardless of stale planned end',
    () {
      final paused = block(
        'paused',
        BlockStatus.paused,
        elapsedSeconds: 15 * 60,
      );
      final result = recalculate([paused], gap: 5);
      expect(result[1].plannedStart, now.add(const Duration(minutes: 50)));
      expectFutureFits(
        result,
        now.add(const Duration(minutes: 50)),
        now.add(const Duration(minutes: 120)),
        5,
      );
    },
  );

  test('second-level active remainder is not rounded down into overlap', () {
    final active = block(
      'active',
      BlockStatus.active,
      planned: 2,
      elapsedSeconds: 61,
    );
    final result = recalculate([active], remaining: 5);
    expect(result[1].plannedStart, now.add(const Duration(seconds: 59)));
    expectFutureFits(
      result,
      now.add(const Duration(seconds: 59)),
      now.add(const Duration(minutes: 5)),
      0,
    );
  });

  test(
    'overtime active work credits actual elapsed time and no negative delay',
    () {
      final result = recalculate(
        [block('active', BlockStatus.active, elapsedSeconds: 120 * 60)],
        remaining: 60,
        gap: 5,
      );
      expect(result[1].plannedStart, now.add(const Duration(minutes: 5)));
      expect(futureTotals(result), {'b': 55});
    },
  );

  test('clock rollback does not create negative running credit', () {
    final result = recalculate([
      block(
        'active',
        BlockStatus.active,
        elapsedSeconds: 30 * 60,
        runningSince: now.add(const Duration(hours: 1)),
      ),
    ]);
    expect(result[1].plannedStart, now.add(const Duration(minutes: 30)));
    expect(futureTotals(result), {'a': 15, 'b': 75});
  });

  test('commitment past deadline preserves history and produces no future', () {
    final active = block('active', BlockStatus.active);
    final result = recalculate([
      active,
      block('old', BlockStatus.pending),
    ], remaining: 20);
    expect(result, [active]);
    expect(identical(result.single, active), isTrue);
  });

  test(
    'elapsed/negative deadline removes pending only, preserving all history',
    () {
      for (final remaining in [0, -30]) {
        final done = block('done', BlockStatus.completed);
        final result = recalculate([
          done,
          block('pending', BlockStatus.pending),
        ], remaining: remaining);
        expect(result, [done]);
        expect(identical(result.single, done), isTrue);
      }
    },
  );

  test(
    'disabled and removed categories retain commitment but receive no new work',
    () {
      final active = block(
        'active',
        BlockStatus.active,
        categoryId: 'removed',
        elapsedSeconds: 30 * 60,
      );
      final result = recalculate(
        [active],
        categories: [
          category('a'),
          category('disabled').copyWith(enabled: false),
        ],
      );
      expect(result.first, same(active));
      expect(futureTotals(result), {'a': 90});
      expect(result[1].plannedStart, now.add(const Duration(minutes: 30)));
    },
  );

  test(
    'repeated checkpoints keep history references and never reuse any IDs',
    () {
      final completed = block(
        'block_0',
        BlockStatus.completed,
        elapsedSeconds: 60 * 60,
      );
      final seen = <String>{completed.id};
      var result = [completed, block('block_1', BlockStatus.pending)];
      seen.add('block_1');
      for (var i = 0; i < 20; i++) {
        result = recalculate(
          result,
          categories: [category('a', maximum: 30), category('b', maximum: 40)],
          gap: 10,
        );
        expect(result.first, same(completed));
        for (final future in result.skip(1)) {
          expect(seen.add(future.id), isTrue);
        }
        expectFutureFits(
          result,
          now,
          now.add(const Duration(minutes: 120)),
          10,
        );
      }
    },
  );
}
