import 'dart:math' as math;

import '../models/app_settings.dart';
import '../models/commitment.dart';
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

/// Thrown when the engine is given input it cannot plan with, such as a
/// negative duration or two categories with the same id. Nothing is planned
/// and nothing is changed. [problem] names the parameter and what to fix, and
/// is safe to show to the user.
class InvalidRoutineInput extends ArgumentError {
  InvalidRoutineInput(String problem, String name) : super(problem, name);

  String get problem => '$message';
}

class RoutineEngine {
  // The counter guarantees uniqueness across calls in this isolate; the random
  // session prefix also avoids reusing persisted IDs after an application restart.
  static final String _idPrefix =
      '${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(1 << 32).toRadixString(16)}';
  static int _nextBlockId = 0;

  /// Subtracts aggregate fixed-event and buffer costs, not a per-block gap.
  /// Prefer [generateRoutine] when the number of gaps is not known yet.
  ///
  /// Throws [InvalidRoutineInput] when any of the three is negative. More fixed
  /// time than total time is not an error: the result is 0.
  static int calculateUsableMinutes({
    required int totalMinutes,
    required int fixedEventMinutes,
    required int bufferMinutes,
  }) {
    _requireNotNegative(totalMinutes, 'totalMinutes');
    _requireNotNegative(fixedEventMinutes, 'fixedEventMinutes');
    _requireNotNegative(bufferMinutes, 'bufferMinutes');
    return math.max<int>(0, totalMinutes - fixedEventMinutes - bufferMinutes);
  }

  // ---------- Input checks ----------
  //
  // Every public method checks its input first and throws
  // [InvalidRoutineInput] instead of quietly clamping or ignoring it, so a
  // wrong value is found and fixed where it comes from. Things the engine is
  // documented to handle are not errors: a window with no room returns no
  // blocks, an unfinished day with no enabled category returns no blocks, and
  // a category minimum above its maximum is lowered to the maximum.

  static void _requireNotNegative(int value, String name) {
    if (value < 0) {
      throw InvalidRoutineInput('$name must not be negative (got $value).', name);
    }
  }

  /// Checks the categories that will be planned (the enabled ones).
  static void _checkCategories(List<Category> categories) {
    final seen = <String>{};
    for (final c in categories.where((c) => c.enabled)) {
      final who = "category '${c.name}'";
      if (c.id.isEmpty) {
        throw InvalidRoutineInput('The $who has an empty id.', 'categories');
      }
      if (!seen.add(c.id)) {
        throw InvalidRoutineInput(
          "Two enabled categories share the id '${c.id}'; ids must be unique.",
          'categories',
        );
      }
      if (!c.percentage.isFinite || c.percentage < 0) {
        throw InvalidRoutineInput(
          'The $who has an invalid share (${c.percentage}); it must be a '
          'number from 0 up.',
          'categories',
        );
      }
      if (c.minimumMinutes < 0) {
        throw InvalidRoutineInput(
          'The $who has a negative minimum (${c.minimumMinutes} min).',
          'categories',
        );
      }
      final max = c.maximumMinutes;
      if (max != null && max < 0) {
        throw InvalidRoutineInput(
          'The $who has a negative maximum ($max min).',
          'categories',
        );
      }
      if (c.blockMinutes < 1) {
        throw InvalidRoutineInput(
          'The $who has a block size of ${c.blockMinutes} min; '
          'it must be at least 1.',
          'categories',
        );
      }
    }
  }

  static void _checkGaps(int bufferMinutes, int? longBreakMinutes) {
    _requireNotNegative(bufferMinutes, 'bufferMinutes');
    if (longBreakMinutes != null) {
      _requireNotNegative(longBreakMinutes, 'longBreakMinutes');
    }
  }

  static void _checkBusy(List<BusyInterval> busy) {
    for (final b in busy) {
      if (b.end.isBefore(b.start)) {
        throw InvalidRoutineInput(
          'A fixed event ends (${b.end}) before it starts (${b.start}).',
          'busy',
        );
      }
    }
  }

  static void _checkUniqueBlockIds(List<Block> blocks, String name) {
    final seen = <String>{};
    for (final b in blocks) {
      if (!seen.add(b.id)) {
        throw InvalidRoutineInput(
          "Two blocks share the id '${b.id}'; ids must be unique.",
          name,
        );
      }
    }
  }

  /// Allocates exactly the nonnegative budget among enabled categories.
  /// Positive finite weights are normalized; other weights receive only their
  /// minimums. If no positive weights exist, surplus is shared equally.
  /// In emergencies, minimums are compressed proportionally, retaining at least
  /// one minute per positive-minimum category whenever the budget permits it.
  /// Input order breaks rounding ties deterministically. IDs must be unique.
  ///
  /// Throws [InvalidRoutineInput] for a negative [usableMinutes] or invalid
  /// categories (see [generateRoutine]).
  static Map<String, int> allocateTime({
    required List<Category> categories,
    required int usableMinutes,
  }) {
    _requireNotNegative(usableMinutes, 'usableMinutes');
    _checkCategories(categories);
    return _allocate(categories, usableMinutes, const {});
  }

  static Map<String, int> _allocate(
    List<Category> categories,
    int minutes,
    Map<String, int> credits,
  ) {
    final enabled = categories.where((c) => c.enabled).toList();
    if (enabled.isEmpty) return {};
    final credited = [for (final c in enabled) credits[c.id] ?? 0];
    // A category's maximum is a daily cap. A minimum above it is lowered to
    // the cap, so the two can never contradict each other.
    final minimums = [
      for (var i = 0; i < enabled.length; i++)
        math.max(
          0,
          math.min(
                enabled[i].minimumMinutes,
                enabled[i].maximumMinutes ?? enabled[i].minimumMinutes,
              ) -
              credited[i],
        ),
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
      [
        for (var i = 0; i < enabled.length; i++)
          enabled[i].maximumMinutes == null
              ? double.infinity
              : math
                    .max(enabled[i].maximumMinutes!, credited[i] + minimums[i])
                    .toDouble(),
      ],
    );
    return {
      for (var i = 0; i < enabled.length; i++)
        enabled[i].id: daily[i] - credited[i],
    };
  }

  /// Weighted water filling with lower bounds and optional upper bounds,
  /// followed by largest-remainder rounding. Unlike independently rounded
  /// shares, this conserves the integer budget. Time that every category's
  /// upper bound refuses is left unallocated instead of overfilling a cap.
  static List<int> _apportion(
    int total,
    List<double> weights,
    List<int> lowerBounds, [
    List<double>? upperBounds,
  ]) {
    final upper =
        upperBounds ?? List<double>.filled(weights.length, double.infinity);
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
      final zeroWeight = <int>[];
      final low = <int>[];
      final high = <int>[];
      var lowExcess = 0.0;
      var highExcess = 0.0;
      for (final i in pending) {
        if (normalized[i] == 0) {
          zeroWeight.add(i);
          continue;
        }
        final share = remaining * normalized[i] / weightSum;
        if (share < lowerBounds[i]) {
          low.add(i);
          lowExcess += lowerBounds[i] - share;
        } else if (share > upper[i]) {
          high.add(i);
          highExcess += share - upper[i];
        }
      }
      if (zeroWeight.isEmpty && low.isEmpty && high.isEmpty) {
        for (final i in pending) {
          targets[i] = remaining * normalized[i] / weightSum;
        }
        break;
      }
      // Clamp only the side with the larger violation first, then
      // redistribute and re-check (standard clamped water filling).
      final toLower = [...zeroWeight, if (lowExcess >= highExcess) ...low];
      final toUpper = [if (highExcess >= lowExcess) ...high];
      for (final i in toLower) {
        targets[i] = lowerBounds[i].toDouble();
        remaining -= lowerBounds[i];
        pending.remove(i);
      }
      for (final i in toUpper) {
        targets[i] = upper[i];
        remaining -= upper[i].toInt();
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
    final targetTotal = upperBounds == null
        ? total
        : targets.fold<double>(0, (sum, t) => sum + t).round();
    var remainder = targetTotal - result.fold<int>(0, (sum, v) => sum + v);
    var index = 0;
    var skipped = 0;
    while (remainder > 0 && skipped < order.length) {
      final i = order[index % order.length];
      index++;
      if (result[i] < upper[i]) {
        result[i]++;
        remainder--;
        skipped = 0;
      } else {
        skipped++;
      }
    }
    return result;
  }

  /// Cuts each category's minutes into blocks of about its block size: the
  /// time is split evenly (see [_blockSizes]), so the sizes stay close to the
  /// chosen one whatever the amount of time.
  ///
  /// Throws [InvalidRoutineInput] for invalid categories, a negative amount of
  /// time, or an [allocation] key that is not one of the [categories].
  static List<Block> splitIntoBlocks({
    required List<Category> categories,
    required Map<String, int> allocation,
  }) {
    _checkCategories(categories);
    final ids = {for (final c in categories) c.id};
    for (final entry in allocation.entries) {
      if (!ids.contains(entry.key)) {
        throw InvalidRoutineInput(
          "The allocation names '${entry.key}', which is not one of the "
          'categories.',
          'allocation',
        );
      }
      if (entry.value < 0) {
        throw InvalidRoutineInput(
          "The allocation for '${entry.key}' is negative (${entry.value}).",
          'allocation',
        );
      }
    }
    return _split(categories, allocation, const {});
  }

  /// Block lengths come in whole steps of this many minutes where possible,
  /// so a routine reads 60, 55, 55 rather than 57, 57, 56.
  static const int _stepMinutes = 5;

  /// Block lengths for [minutes] of a category, first to last.
  ///
  /// The number of blocks is the one whose even split is closest to the
  /// category's block size (`round(minutes / size)`, at least one), and the
  /// time is shared out evenly between them. Taking whole blocks and then
  /// dealing with a leftover (floor division) made the plan jump with every
  /// minute: 179 min became two blocks, one of 119, and only exactly 180 gave
  /// the three expected. Splitting evenly changes smoothly instead: each block
  /// stays within roughly a quarter of the chosen size, 180 -> 60/60/60,
  /// 170 -> 60/55/55, 130 -> 65/65. Less than about one block of time is a
  /// single short block. Sizes are multiples of [_stepMinutes] except that the
  /// last block also takes the few minutes that do not fill a step. The sizes
  /// always add up to [minutes].
  static List<int> _blockSizes(Category category, int minutes) {
    if (minutes <= 0) return const [];
    final size = math.max(1, category.blockMinutes);
    final count = math.max(1, (minutes / size).round());
    final step = minutes ~/ count >= _stepMinutes ? _stepMinutes : 1;
    final steps = minutes ~/ step;
    final rest = minutes - steps * step; // less than one step
    final each = steps ~/ count;
    final extra = steps % count; // the first blocks take one step more
    return [
      for (var i = 0; i < count; i++)
        (each + (i < extra ? 1 : 0)) * step + (i == count - 1 ? rest : 0),
    ];
  }

  static int _blockCount(Category category, int minutes) =>
      _blockSizes(category, minutes).length;

  static List<Block> _split(
    List<Category> categories,
    Map<String, int> allocation,
    Set<String> excludedIds,
  ) => _materialize(_plan(categories, allocation), excludedIds);

  /// Block sizes in category order, without creating any block or ID yet.
  static List<({Category category, int minutes})> _plan(
    List<Category> categories,
    Map<String, int> allocation,
  ) {
    final plan = <({Category category, int minutes})>[];
    for (final category in categories.where((c) => c.enabled)) {
      final minutes = allocation[category.id] ?? 0;
      if (minutes <= 0) continue;
      for (final blockMinutes in _blockSizes(category, minutes)) {
        plan.add((category: category, minutes: blockMinutes));
      }
    }
    return plan;
  }

  static List<Block> _materialize(
    List<({Category category, int minutes})> plan,
    Set<String> excludedIds,
  ) {
    final blocks = <Block>[];
    for (final item in plan) {
      String id;
      do {
        id = 'block_${_idPrefix}_${_nextBlockId++}';
      } while (excludedIds.contains(id));
      blocks.add(
        Block(
          id: id,
          categoryId: item.category.id,
          title: item.category.name,
          plannedDurationMinutes: item.minutes,
        ),
      );
    }
    return blocks;
  }

  /// Free stretches between [start] and [end] once [busy] intervals are cut
  /// out. A block must end [marginMinutes] before a commitment begins.
  static List<BusyInterval> _freeWindows(
    DateTime start,
    DateTime end,
    List<BusyInterval> busy,
    int marginMinutes,
  ) {
    if (!end.isAfter(start)) return [];
    final sorted = busy.where((b) => b.end.isAfter(b.start)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final margin = Duration(minutes: math.max(0, marginMinutes));
    final windows = <BusyInterval>[];
    var cursor = start;
    for (final b in sorted) {
      if (!b.end.isAfter(cursor)) continue; // already behind us
      if (!b.start.isBefore(end)) break;
      final windowEnd = b.start.subtract(margin);
      if (windowEnd.isAfter(cursor)) windows.add((start: cursor, end: windowEnd));
      cursor = b.end;
    }
    if (end.isAfter(cursor)) windows.add((start: cursor, end: end));
    return windows;
  }

  /// First-fit placement of whole blocks into [windows], a [gap] apart.
  /// Returns null when they do not all fit. Blocks are never split around a
  /// commitment: a focus block stays one piece.
  static List<DateTime>? _packStarts(
    List<int> durations,
    List<BusyInterval> windows,
    List<int> gapsAfter,
  ) {
    final starts = <DateTime>[];
    if (durations.isEmpty) return starts;
    if (windows.isEmpty) return null;
    var w = 0;
    var cursor = windows[0].start;
    for (var i = 0; i < durations.length; i++) {
      final minutes = durations[i];
      while (true) {
        if (w >= windows.length) return null;
        final end = cursor.add(Duration(minutes: minutes));
        if (!end.isAfter(windows[w].end)) {
          starts.add(cursor);
          cursor = end.add(Duration(minutes: gapsAfter[i]));
          break;
        }
        w++;
        if (w < windows.length) cursor = windows[w].start;
      }
    }
    return starts;
  }

  static List<Block> _generateAround({
    required List<Category> enabled,
    required DateTime startTime,
    required DateTime dayEnd,
    required int gap,
    required int longGap,
    required Map<String, int> credits,
    required Set<String> excludedIds,
    required List<BusyInterval> busy,
  }) {
    final windows = _freeWindows(startTime, dayEnd, busy, gap);
    final free = windows.fold<int>(
      0,
      (sum, w) => sum + w.end.difference(w.start).inMinutes,
    );
    // Same descent as the open-day case: the biggest budget whose blocks
    // really fit between the commitments. No block or ID exists until then.
    for (var budget = free; budget > 0; budget--) {
      final plan = _plan(enabled, _allocate(enabled, budget, credits));
      final gapsAfter = [
        for (var i = 0; i < plan.length; i++)
          (i + 1 < plan.length &&
                  plan[i + 1].category.id != plan[i].category.id)
              ? longGap
              : gap,
      ];
      final starts = _packStarts(
        [for (final p in plan) p.minutes],
        windows,
        gapsAfter,
      );
      if (starts == null) continue;
      final blocks = _materialize(plan, excludedIds);
      return [
        for (var i = 0; i < blocks.length; i++)
          blocks[i].copyWith(
            plannedStart: starts[i],
            plannedEnd: starts[i].add(
              Duration(minutes: blocks[i].plannedDurationMinutes),
            ),
          ),
      ];
    }
    return [];
  }

  /// Places already-budgeted blocks, with a nonnegative gap between them.
  /// This low-level compatibility API has no deadline; use [generateRoutine]
  /// for deadline-safe allocation, splitting, and placement in one operation.
  ///
  /// Throws [InvalidRoutineInput] for a negative gap or a block that is not at
  /// least one minute long.
  static List<Block> placeOnTimeline({
    required List<Block> blocks,
    required DateTime startTime,
    required int bufferMinutes,
    int? longBreakMinutes,
  }) {
    _checkGaps(bufferMinutes, longBreakMinutes);
    for (final b in blocks) {
      if (b.plannedDurationMinutes < 1) {
        throw InvalidRoutineInput(
          "Block '${b.title}' lasts ${b.plannedDurationMinutes} min; "
          'it must be at least 1.',
          'blocks',
        );
      }
    }
    final placed = <Block>[];
    var cursor = startTime;
    final gap = Duration(minutes: math.max(0, bufferMinutes));
    final longGap = Duration(
      minutes: math.max(0, longBreakMinutes ?? bufferMinutes),
    );
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final end = cursor.add(Duration(minutes: block.plannedDurationMinutes));
      placed.add(block.copyWith(plannedStart: cursor, plannedEnd: end));
      // The last block of a category is followed by the long break.
      final finishesCategory = !blocks
          .skip(i + 1)
          .any((b) => b.categoryId == block.categoryId);
      cursor = end.add(finishesCategory ? longGap : gap);
    }
    return placed;
  }

  /// Generates a routine ending no later than [dayEnd], budgeting every gap
  /// between blocks (no leading/trailing buffer). Durations are whole minutes;
  /// sub-minute remainder is left unused. Nonpositive windows return no blocks.
  ///
  /// Throws [InvalidRoutineInput] when the input is wrong: an enabled category
  /// with an empty or duplicate id, a negative or non-finite share, a negative
  /// minimum or maximum, or a block size under 1 minute; a negative buffer or
  /// long break; or a fixed event that ends before it starts.
  static List<Block> generateRoutine({
    required List<Category> categories,
    required DateTime startTime,
    required DateTime dayEnd,
    required int bufferMinutes,
    int? longBreakMinutes,
    List<BusyInterval> busy = const [],
  }) {
    _checkCategories(categories);
    _checkGaps(bufferMinutes, longBreakMinutes);
    _checkBusy(busy);
    return _generate(
      categories: categories,
      startTime: startTime,
      dayEnd: dayEnd,
      bufferMinutes: bufferMinutes,
      longBreakMinutes: longBreakMinutes,
      credits: const {},
      excludedIds: const {},
      busy: busy,
    );
  }

  static List<Block> _generate({
    required List<Category> categories,
    required DateTime startTime,
    required DateTime dayEnd,
    required int bufferMinutes,
    int? longBreakMinutes,
    required Map<String, int> credits,
    required Set<String> excludedIds,
    List<BusyInterval> busy = const [],
  }) {
    final enabled = categories.where((c) => c.enabled).toList();
    if (enabled.isEmpty) return [];
    final gap = math.max(0, bufferMinutes);
    final longGap = math.max(0, longBreakMinutes ?? bufferMinutes);
    if (busy.isNotEmpty) {
      return _generateAround(
        enabled: enabled,
        startTime: startTime,
        dayEnd: dayEnd,
        gap: gap,
        longGap: longGap,
        credits: credits,
        excludedIds: excludedIds,
        busy: busy,
      );
    }
    final window = dayEnd.difference(startTime).inMinutes;
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
      // Category maximums can leave part of the budget unallocated, so fit
      // what is really planned (equal to [budget] when nothing is capped).
      final planned = allocation.values.fold<int>(0, (sum, v) => sum + v);
      // Blocks are grouped by category: one long break after each category
      // except the last, a normal gap between the other blocks.
      final categoriesUsed = enabled
          .where((c) => (allocation[c.id] ?? 0) > 0)
          .length;
      final longs = math.max(0, categoriesUsed - 1);
      final shorts = math.max(0, count - 1 - longs);
      if (planned + shorts * gap + longs * longGap <= window) {
        return placeOnTimeline(
          blocks: _split(enabled, allocation, excludedIds),
          startTime: startTime,
          bufferMinutes: gap,
          longBreakMinutes: longGap,
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
  ///
  /// Throws [InvalidRoutineInput] for the same reasons as [generateRoutine],
  /// and when two of the [currentBlocks] share an id.
  static List<Block> recalculateFromCheckpoint({
    required List<Block> currentBlocks,
    required List<Category> categories,
    required DateTime now,
    required DateTime dayEnd,
    required int bufferMinutes,
    int? longBreakMinutes,
    List<BusyInterval> busy = const [],
  }) {
    _checkCategories(categories);
    _checkGaps(bufferMinutes, longBreakMinutes);
    _checkBusy(busy);
    _checkUniqueBlockIds(currentBlocks, 'currentBlocks');
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
        longBreakMinutes: longBreakMinutes,
        credits: creditedMinutes,
        excludedIds: currentBlocks.map((b) => b.id).toSet(),
        busy: busy,
      ),
    ];
  }
}
