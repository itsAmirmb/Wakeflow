import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/category.dart';
import 'package:wakeflow/services/routine_engine.dart';
import 'package:wakeflow/data/default_categories.dart';

void main() {
  group('calculateUsableMinutes', () {
    test('Test Case 1: 14h day, 2h fixed events', () {
      final usable = RoutineEngine.calculateUsableMinutes(
        totalMinutes: 14 * 60,
        fixedEventMinutes: 2 * 60,
        bufferMinutes: 0,
      );
      expect(usable, 12 * 60); // 720 minutes, matches spec §6
    });
  });

  group('allocateTime', () {
    test('Test Case 1: normal case matches spec example (§6)', () {
      final allocation = RoutineEngine.allocateTime(
        categories: defaultCategories,
        usableMinutes: 12 * 60, // 720
      );
      // Academic 40% = 288m (4h48m), Trading 25% = 180m (3h),
      // Gym/Fun 35% = 252m (4h12m) — all above their minimums.
      expect(allocation['academic'], 288);
      expect(allocation['trading'], 180);
      expect(allocation['gym_fun'], 252);
    });

    test('Test Case 2: only 4h usable — minimums still fit', () {
      final allocation = RoutineEngine.allocateTime(
        categories: defaultCategories,
        usableMinutes: 4 * 60, // 240
      );
      // Percentage targets: 96/60/84 — all >= minimums (60/30/60)
      // so no compression needed.
      final total = allocation.values.fold<int>(0, (s, m) => s + m);
      expect(total, lessThanOrEqualTo(240));
      expect(allocation['academic']! >= 60, true);
      expect(allocation['trading']! >= 30, true);
      expect(allocation['gym_fun']! >= 60, true);
    });

    test('Test Case 3: only 90m usable — emergency compression', () {
      final allocation = RoutineEngine.allocateTime(
        categories: defaultCategories,
        usableMinutes: 90,
      );
      // Total minimums = 60+30+60 = 150 > 90 usable -> compression.
      final total = allocation.values.fold<int>(0, (s, m) => s + m);
      expect(total, lessThanOrEqualTo(90));
      // No category should be zero/dropped.
      expect(allocation.values.every((m) => m > 0), true);
    });

    test('Test Case 4: minimums exceed available time entirely', () {
      final allocation = RoutineEngine.allocateTime(
        categories: defaultCategories,
        usableMinutes: 10,
      );
      final total = allocation.values.fold<int>(0, (s, m) => s + m);
      expect(total, lessThanOrEqualTo(10));
    });
  });

  group('splitIntoBlocks', () {
    test('Academic 288m splits into blocks within 60-90m range', () {
      final blocks = RoutineEngine.splitIntoBlocks(
        categories: [defaultCategories[0]], // Academic
        allocation: {'academic': 288},
      );
      final total = blocks.fold<int>(
        0, (s, b) => s + b.plannedDurationMinutes);
      expect(total, 288);
      for (final b in blocks) {
        expect(b.plannedDurationMinutes, lessThanOrEqualTo(90));
      }
    });
  });
}