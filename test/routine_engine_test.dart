import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/data/default_categories.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/models/category.dart';
import 'package:wakeflow/services/routine_engine.dart';

Category category(
  String id, {
  double weight = 1,
  int minimum = 0,
  int blockMin = 1,
  int blockMax = 90,
  bool enabled = true,
}) => Category(
  id: id,
  name: id,
  icon: '',
  percentage: weight,
  minimumMinutes: minimum,
  preferredBlockMinMinutes: blockMin,
  preferredBlockMaxMinutes: blockMax,
  enabled: enabled,
);

int total(Iterable<int> minutes) =>
    minutes.fold(0, (sum, value) => sum + value);

void expectTimeline(List<Block> blocks, DateTime start, DateTime end, int gap) {
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    expect(block.plannedDurationMinutes, greaterThan(0));
    expect(block.plannedStart!.isBefore(start), isFalse);
    expect(block.plannedEnd!.isAfter(end), isFalse);
    expect(
      block.plannedEnd!.difference(block.plannedStart!).inMinutes,
      block.plannedDurationMinutes,
    );
    if (i > 0) {
      expect(
        block.plannedStart!.difference(blocks[i - 1].plannedEnd!).inMinutes,
        gap,
      );
    }
  }
  expect(blocks.map((b) => b.id).toSet().length, blocks.length);
}

void main() {
  group('calculateUsableMinutes', () {
    test('subtracts aggregate fixed events and buffers, clamps to zero', () {
      expect(
        RoutineEngine.calculateUsableMinutes(
          totalMinutes: 840,
          fixedEventMinutes: 120,
          bufferMinutes: 30,
        ),
        690,
      );
      expect(
        RoutineEngine.calculateUsableMinutes(
          totalMinutes: 10,
          fixedEventMinutes: 20,
          bufferMinutes: 5,
        ),
        0,
      );
      expect(
        RoutineEngine.calculateUsableMinutes(
          totalMinutes: 10,
          fixedEventMinutes: -20,
          bufferMinutes: -5,
        ),
        10,
      );
    });
  });

  group('allocateTime', () {
    test('retains the default 720 minute specification example', () {
      expect(
        RoutineEngine.allocateTime(
          categories: defaultCategories,
          usableMinutes: 720,
        ),
        {'academic': 288, 'trading': 180, 'gym_fun': 252},
      );
    });

    test(
      'normalizes enabled positive weights without allocating disabled work',
      () {
        expect(
          RoutineEngine.allocateTime(
            categories: [
              category('a', weight: 20),
              category('b', weight: 10),
              category('off', weight: 1000, minimum: 100, enabled: false),
            ],
            usableMinutes: 90,
          ),
          {'a': 60, 'b': 30},
        );
      },
    );

    test(
      'largest remainders conserve minutes, with stable input-order ties',
      () {
        final categories = [category('a'), category('b'), category('c')];
        expect(
          RoutineEngine.allocateTime(categories: categories, usableMinutes: 2),
          {'a': 1, 'b': 1, 'c': 0},
        );
        expect(
          RoutineEngine.allocateTime(categories: categories, usableMinutes: 10),
          {'a': 4, 'b': 3, 'c': 3},
        );
      },
    );

    test(
      'protects feasible minimums while redistributing overweight shares',
      () {
        expect(
          RoutineEngine.allocateTime(
            categories: [
              category('a', weight: 0.98),
              category('b', weight: 0.01, minimum: 30),
              category('c', weight: 0.01, minimum: 30),
            ],
            usableMinutes: 100,
          ),
          {'a': 40, 'b': 30, 'c': 30},
        );
      },
    );

    test('emergency shares are proportional and conserve the remainder', () {
      final categories = [
        category('a', minimum: 60),
        category('b', minimum: 30),
        category('c', minimum: 60),
        category('zero', minimum: 0),
      ];
      expect(
        RoutineEngine.allocateTime(categories: categories, usableMinutes: 91),
        {'a': 37, 'b': 18, 'c': 36, 'zero': 0},
      );
      expect(
        RoutineEngine.allocateTime(categories: categories, usableMinutes: 1),
        {'a': 1, 'b': 0, 'c': 0, 'zero': 0},
      );
    });

    test(
      'skewed emergency minimums do not cause avoidable zero categories',
      () {
        final categories = [
          category('a', minimum: 10000),
          category('b', minimum: 1),
          category('c', minimum: 1),
        ];
        expect(
          RoutineEngine.allocateTime(categories: categories, usableMinutes: 3),
          {'a': 1, 'b': 1, 'c': 1},
        );
        expect(
          RoutineEngine.allocateTime(categories: categories, usableMinutes: 10),
          {'a': 8, 'b': 1, 'c': 1},
        );
      },
    );

    test('invalid weights receive minima only if a positive weight exists', () {
      expect(
        RoutineEngine.allocateTime(
          categories: [
            category('positive', weight: 2),
            category('zero', weight: 0, minimum: 2),
            category('negative', weight: -1, minimum: 2),
            category('nan', weight: double.nan, minimum: 2),
            category('infinite', weight: double.infinity, minimum: 2),
          ],
          usableMinutes: 20,
        ),
        {'positive': 12, 'zero': 2, 'negative': 2, 'nan': 2, 'infinite': 2},
      );
    });

    test('all-zero weights fall back to equal shares, retaining minima', () {
      expect(
        RoutineEngine.allocateTime(
          categories: [
            category('a', weight: 0, minimum: 8),
            category('b', weight: -1),
          ],
          usableMinutes: 10,
        ),
        {'a': 8, 'b': 2},
      );
    });

    test('large finite weights cannot overflow their normalization', () {
      expect(
        RoutineEngine.allocateTime(
          categories: [
            category('a', weight: 1e308),
            category('b', weight: 1e308),
          ],
          usableMinutes: 99,
        ),
        {'a': 50, 'b': 49},
      );
    });

    test('empty, disabled, zero and negative budgets are safe', () {
      expect(
        RoutineEngine.allocateTime(categories: [], usableMinutes: 10),
        isEmpty,
      );
      expect(
        RoutineEngine.allocateTime(
          categories: [category('off', enabled: false)],
          usableMinutes: 10,
        ),
        isEmpty,
      );
      for (final budget in [-10, 0]) {
        expect(
          RoutineEngine.allocateTime(
            categories: [category('a', minimum: 100)],
            usableMinutes: budget,
          ),
          {'a': 0},
        );
      }
    });

    test(
      'deterministic sweep conserves budgets and every feasible minimum',
      () {
        for (var seed = 0; seed < 20; seed++) {
          final categories = [
            for (var i = 0; i < 4; i++)
              category(
                '$i',
                weight: ((seed + i * 3) % 7).toDouble(),
                minimum: (seed * 3 + i * 7) % 25,
              ),
          ];
          final minimumTotal = total(categories.map((c) => c.minimumMinutes));
          final positiveCount = categories
              .where((c) => c.minimumMinutes > 0)
              .length;
          for (var minutes = 0; minutes <= 160; minutes++) {
            final allocation = RoutineEngine.allocateTime(
              categories: categories,
              usableMinutes: minutes,
            );
            expect(
              total(allocation.values),
              minutes,
              reason: 'seed=$seed, minutes=$minutes',
            );
            for (final c in categories) {
              expect(allocation[c.id], greaterThanOrEqualTo(0));
              if (minutes >= minimumTotal) {
                expect(
                  allocation[c.id],
                  greaterThanOrEqualTo(c.minimumMinutes),
                );
              } else if (minutes >= positiveCount && c.minimumMinutes > 0) {
                expect(allocation[c.id], greaterThan(0));
              }
            }
          }
        }
      },
    );
  });

  group('splitIntoBlocks', () {
    test('288 academic minutes use four valid blocks without an 18m tail', () {
      final blocks = RoutineEngine.splitIntoBlocks(
        categories: [defaultCategories.first],
        allocation: {'academic': 288},
      );
      expect(blocks.map((b) => b.plannedDurationMinutes), [72, 72, 72, 72]);
      expect(blocks.every((b) => b.status == BlockStatus.pending), isTrue);
      expect(
        blocks.every(
          (b) => b.categoryId == 'academic' && b.title == 'Academic',
        ),
        isTrue,
      );
    });

    test(
      'single short allocations survive, disabled/zero allocations do not',
      () {
        final blocks = RoutineEngine.splitIntoBlocks(
          categories: [
            category('a', blockMin: 60),
            category('zero'),
            category('off', enabled: false),
          ],
          allocation: {'a': 10, 'zero': 0, 'off': 90},
        );
        expect(blocks.map((b) => b.plannedDurationMinutes), [10]);
      },
    );

    test(
      'invalid maxima cannot create zero-sized blocks or infinite loops',
      () {
        final blocks = RoutineEngine.splitIntoBlocks(
          categories: [category('a', blockMin: 60, blockMax: 0)],
          allocation: {'a': 3},
        );
        expect(blocks.map((b) => b.plannedDurationMinutes), [1, 1, 1]);
      },
    );

    test('IDs remain unique over many consecutive split calls', () {
      final ids = <String>{};
      for (var i = 0; i < 100; i++) {
        final blocks = RoutineEngine.splitIntoBlocks(
          categories: [category('a')],
          allocation: {'a': 200},
        );
        for (final block in blocks) {
          expect(ids.add(block.id), isTrue);
        }
      }
    });

    test('sweep meets both bounds whenever mathematically feasible', () {
      for (final minimum in [1, 15, 30, 60]) {
        for (final maximum in [30, 60, 90]) {
          for (var minutes = 1; minutes <= 300; minutes++) {
            final blocks = RoutineEngine.splitIntoBlocks(
              categories: [category('a', blockMin: minimum, blockMax: maximum)],
              allocation: {'a': minutes},
            );
            final durations = blocks.map((b) => b.plannedDurationMinutes);
            expect(total(durations), minutes);
            expect(durations.every((m) => m > 0 && m <= maximum), isTrue);
            final smallestCount = (minutes + maximum - 1) ~/ maximum;
            if (smallestCount * minimum <= minutes) {
              expect(durations.every((m) => m >= minimum), isTrue);
            }
            expect(
              durations.reduce((a, b) => a > b ? a : b) -
                  durations.reduce((a, b) => a < b ? a : b),
              lessThanOrEqualTo(1),
            );
          }
        }
      }
    });
  });

  group('generateRoutine', () {
    final start = DateTime(2026, 1, 1, 8);

    test('budgets every gap and fills a feasible deadline exactly', () {
      final end = start.add(const Duration(minutes: 300));
      final blocks = RoutineEngine.generateRoutine(
        categories: [category('a', blockMin: 60, blockMax: 90)],
        startTime: start,
        dayEnd: end,
        bufferMinutes: 10,
      );
      expect(blocks.map((b) => b.plannedDurationMinutes), [90, 90, 90]);
      expectTimeline(blocks, start, end, 10);
      // 270 productive minutes + 20 gaps leaves ten unusable minutes: a
      // fourth block would require another gap and reduce productive capacity.
      expect(blocks.last.plannedEnd, start.add(const Duration(minutes: 290)));
    });

    test('single block is not charged a leading or trailing buffer', () {
      final end = start.add(const Duration(minutes: 50));
      final blocks = RoutineEngine.generateRoutine(
        categories: [category('a')],
        startTime: start,
        dayEnd: end,
        bufferMinutes: 100,
      );
      expect(blocks.single.plannedDurationMinutes, 50);
      expect(blocks.single.plannedEnd, end);
    });

    test('huge gaps still retain feasible productive work', () {
      final end = start.add(const Duration(minutes: 3));
      final blocks = RoutineEngine.generateRoutine(
        categories: [category('a', minimum: 10), category('b', minimum: 10)],
        startTime: start,
        dayEnd: end,
        bufferMinutes: 100,
      );
      expect(blocks.length, 1);
      expectTimeline(blocks, start, end, 100);
    });

    test('nonpositive windows, empty and disabled categories return empty', () {
      for (final minutes in [-20, 0]) {
        expect(
          RoutineEngine.generateRoutine(
            categories: defaultCategories,
            startTime: start,
            dayEnd: start.add(Duration(minutes: minutes)),
            bufferMinutes: 10,
          ),
          isEmpty,
        );
      }
      for (final categories in <List<Category>>[
        [],
        [category('off', enabled: false)],
      ]) {
        expect(
          RoutineEngine.generateRoutine(
            categories: categories,
            startTime: start,
            dayEnd: start.add(const Duration(hours: 8)),
            bufferMinutes: 10,
          ),
          isEmpty,
        );
      }
    });

    test('negative gap is clamped, sub-minute remainder never overruns', () {
      final end = start.add(const Duration(minutes: 100, seconds: 59));
      final blocks = RoutineEngine.generateRoutine(
        categories: [category('a', blockMax: 40)],
        startTime: start,
        dayEnd: end,
        bufferMinutes: -10,
      );
      expect(total(blocks.map((b) => b.plannedDurationMinutes)), 100);
      expectTimeline(blocks, start, end, 0);
    });

    test('deterministic window/gap sweep always respects exact deadlines', () {
      for (final gap in [0, 1, 10, 45, 200]) {
        for (var minutes = 1; minutes <= 400; minutes += 7) {
          final end = start.add(Duration(minutes: minutes));
          final blocks = RoutineEngine.generateRoutine(
            categories: defaultCategories,
            startTime: start,
            dayEnd: end,
            bufferMinutes: gap,
          );
          expect(blocks, isNotEmpty);
          expectTimeline(blocks, start, end, gap);
          expect(
            total(blocks.map((b) => b.plannedDurationMinutes)) +
                (blocks.length - 1) * gap,
            lessThanOrEqualTo(minutes),
          );
        }
      }
    });
  });
}
