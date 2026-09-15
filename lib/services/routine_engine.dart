import '../models/category.dart';
import '../models/block.dart';

class RoutineEngine {
  /// Steps 1-4: usable time = total - fixed events - buffers.
  static int calculateUsableMinutes({
    required int totalMinutes,
    required int fixedEventMinutes,
    required int bufferMinutes,
  }) {
    final usable = totalMinutes - fixedEventMinutes - bufferMinutes;
    return usable > 0 ? usable : 0;
  }

  /// Steps 5-7: allocate usable time across enabled categories,
  /// respecting minimums, with emergency compression if minimums
  /// exceed available time.
  static Map<String, int> allocateTime({
    required List<Category> categories,
    required int usableMinutes,
  }) {
    final enabled = categories.where((c) => c.enabled).toList();
    if (enabled.isEmpty) return {};

    // Step 5: target allocation by percentage.
    final Map<String, int> targetAllocation = {
      for (final c in enabled) c.id: (usableMinutes * c.percentage).round(),
    };

    // Step 6: apply minimums — never allocate less than minimum
    // as long as we're not yet in emergency compression.
    final totalMinimums =
        enabled.fold<int>(0, (sum, c) => sum + c.minimumMinutes);

    if (totalMinimums > usableMinutes) {
      // Step 7: Emergency Compression — scale all minimums down
      // proportionally so they sum to usableMinutes. No category
      // is dropped, per spec rule.
      if (usableMinutes <= 0) {
        return {for (final c in enabled) c.id: 0};
      }
      final scale = usableMinutes / totalMinimums;
      return {
        for (final c in enabled)
          c.id: (c.minimumMinutes * scale).floor(),
      };
    }

    // Normal case: use percentage target, but never below minimum.
    final Map<String, int> allocation = {
      for (final c in enabled)
        c.id: targetAllocation[c.id]! < c.minimumMinutes
            ? c.minimumMinutes
            : targetAllocation[c.id]!,
    };

    // If bumping categories up to their minimums pushed the total
    // over usableMinutes, scale the excess back down from the
    // categories that were above minimum (proportionally), so we
    // never exceed usableMinutes. Categories at their minimum are
    // protected and not reduced further.
    final allocatedTotal =
        allocation.values.fold<int>(0, (sum, m) => sum + m);
    final overflow = allocatedTotal - usableMinutes;

    if (overflow > 0) {
      final aboveMinimum = enabled
          .where((c) => allocation[c.id]! > c.minimumMinutes)
          .toList();
      final reducibleTotal = aboveMinimum.fold<int>(
        0,
        (sum, c) => sum + (allocation[c.id]! - c.minimumMinutes),
      );

      if (reducibleTotal > 0) {
        for (final c in aboveMinimum) {
          final reducible = allocation[c.id]! - c.minimumMinutes;
          final share = (reducible / reducibleTotal) * overflow;
          allocation[c.id] = allocation[c.id]! - share.round();
        }
      }
    }

    return allocation;
  }

  /// Step 8: split each category's total minutes into blocks sized
  /// within [preferredBlockMinMinutes, preferredBlockMaxMinutes].
  static List<Block> splitIntoBlocks({
    required List<Category> categories,
    required Map<String, int> allocation,
  }) {
    final List<Block> blocks = [];
    int blockCounter = 0;

    for (final category in categories) {
      var remaining = allocation[category.id] ?? 0;
      if (remaining <= 0) continue;

      // If total time is less than one minimum-size block, make a
      // single short block rather than producing zero blocks.
      if (remaining < category.preferredBlockMinMinutes) {
        blocks.add(Block(
          id: 'block_${blockCounter++}',
          categoryId: category.id,
          title: category.name,
          plannedDurationMinutes: remaining,
        ));
        continue;
      }

      while (remaining > 0) {
        int blockSize;
        if (remaining <= category.preferredBlockMaxMinutes) {
          // Last chunk fits in one block.
          blockSize = remaining;
        } else {
          blockSize = category.preferredBlockMaxMinutes;
        }
        blocks.add(Block(
          id: 'block_${blockCounter++}',
          categoryId: category.id,
          title: category.name,
          plannedDurationMinutes: blockSize,
        ));
        remaining -= blockSize;
      }
    }

    return blocks;
  }
}