import 'dart:math' as math;

import '../models/app_settings.dart';
import '../models/category.dart';
import '../models/block.dart';

/// Outcome of [RoutineEngine.distill]: what is kept and what is dropped.
class DistillResult {
  /// The day's blocks after distillation (completed + partial only).
  final List<Block> blocks;
  final List<Block> completed;
  final List<Block> partial;
  final List<Block> discarded;

  const DistillResult({
    required this.blocks,
    required this.completed,
    required this.partial,
    required this.discarded,
  });

  int get partialSeconds =>
      partial.fold(0, (sum, b) => sum + b.accumulatedSeconds);
  int get discardedPlannedMinutes =>
      discarded.fold(0, (sum, b) => sum + b.plannedDurationMinutes);
}

class RoutineEngine {
  // The counter guarantees uniqueness across calls in this isolate; the random
  // session prefix also avoids reusing persisted IDs after an application restart.
  static final String _idPrefix =
      '${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(1 << 32).toRadixString(16)}';
  static int _nextBlockId = 0;

  /// Subtracts aggregate fixed-event and buffer costs, not a per-block gap.
  /// Prefer [generateRoutine] when the number of gaps is not known yet.
  static int calculateUsableMinutes({
    required int totalMinutes,
    required int fixedEventMinutes,
    required int bufferMinutes,
  }) => math.max<int>(
    0,
    totalMinutes -
        math.max<int>(0, fixedEventMinutes) -
        math.max<int>(0, bufferMinutes),
  );

  /// Allocates exactly the nonnegative budget among enabled categories.
  /// Positive finite weights are normalized; other weights receive only their
  /// minimums. If no positive weights exist, surplus is shared equally.
  /// In emergencies, minimums are compressed proportionally, retaining at least
  /// one minute per positive-minimum category whenever the budget permits it.
  /// Input order breaks rounding ties deterministically. IDs must be unique.
  static Map<String, int> allocateTime({
    required List<Category> categories,
    required int usableMinutes,
  }) => _allocate(categories, math.max(0, usableMinutes), const {});

  static Map<String, int> _allocate(
    List<Category> categories,
    int minutes,
    Map<String, int> credits,
  ) {
    final enabled = categories.where((c) => c.enabled).toList();
    if (enabled.isEmpty) return {};
    final credited = [for (final c in enabled) credits[c.id] ?? 0];
    final minimums = [
      for (var i = 0; i < enabled.length; i++)
        math.max(0, enabled[i].minimumMinutes - credited[i]),
    ];
    final totalMinimum = minimums.fold<int>(0, (sum, value) => sum + value);
    if (totalMinimum > minutes) {
      final positiveCount = minimums.where((value) => value > 0).length;
      final compressed = _apportion(
        minutes,
        [for (final minimum in minimums) minimum.toDouble()],
        [
          for (final minimum in minimums)
            minutes >= positiveCount && minimum > 0 ? 1 : 0,
        ],
      );
      return {
        for (var i = 0; i < enabled.length; i++) enabled[i].id: compressed[i],
      };
    }

    // Allocate the whole day's productive time, with already completed/current
    // work as lower bounds, then return only the as-yet-uncommitted portion.
    final daily = _apportion(
      minutes + credited.fold<int>(0, (sum, value) => sum + value),
      [
        for (final c in enabled)
          c.percentage.isFinite && c.percentage > 0 ? c.percentage : 0,
      ],
      [for (var i = 0; i < enabled.length; i++) credited[i] + minimums[i]],
    );
    return {
      for (var i = 0; i < enabled.length; i++)
        enabled[i].id: daily[i] - credited[i],
    };
  }

  /// Lower-bound weighted water filling followed by largest-remainder rounding.
  /// Unlike independently rounded shares, this conserves the integer budget.
  static List<int> _apportion(
    int total,
    List<double> weights,
    List<int> lowerBounds,
  ) {
    final largestWeight = weights.fold<double>(0, math.max);
    // Scaling first prevents a sum of large finite weights from overflowing.
    final normalized = [
      for (final weight in weights)
        largestWeight > 0 ? weight / largestWeight : 1.0,
    ];
    final targets = List<double>.filled(weights.length, 0);
    final pending = [for (var i = 0; i < weights.length; i++) i];
    var remaining = total;
    while (pending.isNotEmpty) {
      final weightSum = pending.fold<double>(
        0,
        (sum, i) => sum + normalized[i],
      );
      final fixed = [
        for (final i in pending)
          if (normalized[i] == 0 ||
              remaining * normalized[i] / weightSum < lowerBounds[i])
            i,
      ];
      if (fixed.isEmpty) {
        for (final i in pending) {
          targets[i] = remaining * normalized[i] / weightSum;
        }
        break;
      }
      for (final i in fixed) {
        targets[i] = lowerBounds[i].toDouble();
        remaining -= lowerBounds[i];
        pending.remove(i);
      }
    }
    final result = [for (final target in targets) target.floor()];
    final order = [for (var i = 0; i < targets.length; i++) i]
      ..sort((a, b) {
        final comparison = (targets[b] - result[b]).compareTo(
          targets[a] - result[a],
        );
        return comparison != 0 ? comparison : a.compareTo(b);
      });
    final remainder = total - result.fold<int>(0, (sum, value) => sum + value);
    for (var i = 0; i < remainder; i++) {
      result[order[i % order.length]]++;
    }
    return result;
  }

  /// Uses the fewest blocks permitted by the positive maximum, distributing
  /// minutes evenly instead of leaving a tiny tail. If any split can satisfy
  /// both preferred bounds, this split does. If not, the maximum is retained
  /// and shorter blocks are unavoidable. Nonpositive maxima are treated as 1.
  static List<Block> splitIntoBlocks({
    required List<Category> categories,
    required Map<String, int> allocation,
  }) => _split(categories, allocation, const {});

  static int _blockCount(Category category, int minutes) {
    final maximum = math.max(1, category.preferredBlockMaxMinutes);
    return (minutes + maximum - 1) ~/ maximum;
  }

  static List<Block> _split(
    List<Category> categories,
    Map<String, int> allocation,
    Set<String> excludedIds,
  ) {
    final blocks = <Block>[];
    for (final category in categories.where((c) => c.enabled)) {
      final minutes = allocation[category.id] ?? 0;
      if (minutes <= 0) continue;
      final count = _blockCount(category, minutes);
      for (var i = 0; i < count; i++) {
        String id;
        do {
          id = 'block_${_idPrefix}_${_nextBlockId++}';
        } while (excludedIds.contains(id));
        blocks.add(
          Block(
            id: id,
            categoryId: category.id,
            title: category.name,
            plannedDurationMinutes:
                minutes ~/ count + (i < minutes % count ? 1 : 0),
          ),
        );
      }
    }
    return blocks;
  }

  /// Places already-budgeted blocks, with a nonnegative gap between them.
  /// This low-level compatibility API has no deadline; use [generateRoutine]
  /// for deadline-safe allocation, splitting, and placement in one operation.
  static List<Block> placeOnTimeline({
    required List<Block> blocks,
    required DateTime startTime,
    required int bufferMinutes,
  }) {
    final placed = <Block>[];
    var cursor = startTime;
    final gap = Duration(minutes: math.max(0, bufferMinutes));
    for (final block in blocks) {
      final end = cursor.add(Duration(minutes: block.plannedDurationMinutes));
      placed.add(block.copyWith(plannedStart: cursor, plannedEnd: end));
      cursor = end.add(gap);
    }
    return placed;
  }

  /// Generates a routine ending no later than [dayEnd], budgeting every gap
  /// between blocks (no leading/trailing buffer). Durations are whole minutes;
  /// sub-minute remainder is left unused. Nonpositive windows return no blocks.
  static List<Block> generateRoutine({
    required List<Category> categories,
    required DateTime startTime,
    required DateTime dayEnd,
    required int bufferMinutes,
  }) => _generate(
    categories: categories,
    startTime: startTime,
    dayEnd: dayEnd,
    bufferMinutes: bufferMinutes,
    credits: const {},
    excludedIds: const {},
  );

  static List<Block> _generate({
    required List<Category> categories,
    required DateTime startTime,
    required DateTime dayEnd,
    required int bufferMinutes,
    required Map<String, int> credits,
    required Set<String> excludedIds,
  }) {
    final enabled = categories.where((c) => c.enabled).toList();
    if (enabled.isEmpty) return [];
    final window = dayEnd.difference(startTime).inMinutes;
    final gap = math.max(0, bufferMinutes);
    // Descend to the greatest feasible productive budget. Integer apportionment
    // can change category/block counts non-monotonically, so binary search (or
    // iteratively subtracting the previous gap estimate) can miss a valid fit.
    // No blocks/IDs are created until a feasible allocation has been found.
    for (var budget = window; budget > 0; budget--) {
      final allocation = _allocate(enabled, budget, credits);
      final count = enabled.fold<int>(
        0,
        (sum, category) =>
            sum + _blockCount(category, allocation[category.id]!),
      );
      if (budget + math.max(0, count - 1) * gap <= window) {
        return placeOnTimeline(
          blocks: _split(enabled, allocation, excludedIds),
          startTime: startTime,
          bufferMinutes: gap,
        );
      }
    }
    return [];
  }

  /// Distillation: keeps what is real and drops the rest. It does not plan
  /// anything new; planning the remaining time is Start Day's job.
  ///
  /// - Completed and partial blocks are always kept untouched.
  /// - Active, paused and skipped blocks whose recorded progress reaches the
  ///   user's threshold become [BlockStatus.partial] (time done, kept in
  ///   stats); below it they are discarded.
  /// - Pending and cancelled blocks are discarded.
  static DistillResult distill({
    required List<Block> currentBlocks,
    required DateTime now,
    required AppSettings settings,
  }) {
    final completed = <Block>[];
    final partial = <Block>[];
    final discarded = <Block>[];
    for (final block in currentBlocks) {
      switch (block.status) {
        case BlockStatus.completed:
          completed.add(block);
        case BlockStatus.partial:
          partial.add(block);
        case BlockStatus.cancelled:
          break; // stale leftovers from an earlier recalculation
        case BlockStatus.pending:
          discarded.add(block);
        case BlockStatus.active:
        case BlockStatus.paused:
        case BlockStatus.skipped:
          final elapsed = block.elapsedAt(now);
          if (settings.isProgressKept(
            elapsed: elapsed,
            plannedMinutes: block.plannedDurationMinutes,
          )) {
            final seconds = elapsed.inSeconds;
            partial.add(
              block.copyWith(
                status: BlockStatus.partial,
                actualEnd: block.actualEnd ?? now,
                accumulatedSeconds: seconds,
                runningSince: null,
                plannedDurationMinutes: math.max(1, (seconds + 59) ~/ 60),
              ),
            );
          } else {
            discarded.add(block);
          }
      }
    }
    final kept = [...completed, ...partial]
      ..sort((a, b) {
        final x = a.plannedStart, y = b.plannedStart;
        if (x == null || y == null) return 0;
        return x.compareTo(y);
      });
    return DistillResult(
      blocks: kept,
      completed: completed,
      partial: partial,
      discarded: discarded,
    );
  }

  /// Replaces only pending blocks. Every nonpending object/ID is preserved.
  /// Completed work credits stored active seconds (or legacy actual timestamps
  /// when no seconds were stored), never its planned duration. Active/paused
  /// work credits elapsed time plus remaining planned commitment. Paused work
  /// is treated as resuming now; its unbounded future pause cannot be predicted.
  /// Future work starts after now, all remaining commitments, and their gaps.
  /// Existing immutable blocks may themselves extend past the deadline; in that
  /// case they are retained and no additional work is generated.
  static List<Block> recalculateFromCheckpoint({
    required List<Block> currentBlocks,
    required List<Category> categories,
    required DateTime now,
    required DateTime dayEnd,
    required int bufferMinutes,
  }) {
    final untouched = currentBlocks
        .where((b) => b.status != BlockStatus.pending)
        .toList();
    final credits = <String, int>{};
    final gap = Duration(minutes: math.max(0, bufferMinutes));
    var startTime = now;
    for (final block in untouched) {
      var creditedSeconds = 0;
      if (block.status == BlockStatus.completed ||
          block.status == BlockStatus.partial) {
        creditedSeconds = math.max(0, block.accumulatedSeconds);
        if (creditedSeconds == 0 &&
            block.actualStart != null &&
            block.actualEnd != null) {
          creditedSeconds = math.max(
            0,
            block.actualEnd!.difference(block.actualStart!).inSeconds,
          );
        }
      } else if (block.status == BlockStatus.active ||
          block.status == BlockStatus.paused) {
        final runningSeconds =
            block.status == BlockStatus.active && block.runningSince != null
            ? math.max(0, now.difference(block.runningSince!).inSeconds)
            : 0;
        final elapsedSeconds =
            math.max(0, block.accumulatedSeconds) + runningSeconds;
        final remainingSeconds = math.max(
          0,
          block.plannedDurationMinutes * 60 - elapsedSeconds,
        );
        creditedSeconds = elapsedSeconds + remainingSeconds;
        startTime = startTime.add(Duration(seconds: remainingSeconds)).add(gap);
      }
      credits.update(
        block.categoryId,
        (value) => value + creditedSeconds,
        ifAbsent: () => creditedSeconds,
      );
    }
    // Aggregate seconds before truncation so multiple short completed blocks
    // can together satisfy a minute of the daily allocation.
    final creditedMinutes = {
      for (final entry in credits.entries) entry.key: entry.value ~/ 60,
    };
    return [
      ...untouched,
      ..._generate(
        categories: categories,
        startTime: startTime,
        dayEnd: dayEnd,
        bufferMinutes: bufferMinutes,
        credits: creditedMinutes,
        excludedIds: currentBlocks.map((b) => b.id).toSet(),
      ),
    ];
  }
}
