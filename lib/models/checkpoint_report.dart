import 'dart:math' as math;

import 'block.dart';
import 'category.dart';

enum CheckpointAssessment { reached, partial, notReached }

class CategoryProgress {
  final Category category;
  final int targetSeconds;
  final int expectedSeconds;
  final int actualSeconds;

  const CategoryProgress({
    required this.category,
    required this.targetSeconds,
    required this.expectedSeconds,
    required this.actualSeconds,
  });

  int get targetMinutes => targetSeconds ~/ 60;
  int get expectedMinutes => expectedSeconds ~/ 60;
  int get doneMinutes => actualSeconds ~/ 60;
}

/// A snapshot of the current plan, not a moving percentage of the whole day.
/// Time recorded is evidence for reflection, never proof of task completion.
class CheckpointReport {
  final DateTime now;
  final DateTime dayEnd;
  final List<CategoryProgress> categories;

  const CheckpointReport({
    required this.now,
    required this.dayEnd,
    required this.categories,
  });

  int get remainingMinutes => math.max(0, dayEnd.difference(now).inMinutes);

  factory CheckpointReport.fromBlocks({
    required List<Block> blocks,
    required List<Category> categories,
    required DateTime now,
    required DateTime dayEnd,
  }) {
    final included = <String, Category>{for (final c in categories) c.id: c};
    // Retain evidence even if its category was subsequently removed.
    for (final block in blocks) {
      included.putIfAbsent(
        block.categoryId,
        () => Category(
          id: block.categoryId,
          name: block.title,
          icon: '',
          percentage: 0,
          minimumMinutes: 0,
          preferredBlockMinMinutes: 1,
          preferredBlockMaxMinutes: 60,
          priority: 0,
        ),
      );
    }
    final order = [for (final c in categories) c.id];
    for (final block in blocks) {
      if (!order.contains(block.categoryId)) order.add(block.categoryId);
    }
    return CheckpointReport(
      now: now,
      dayEnd: dayEnd,
      categories: [
        for (final id in order) _progress(included[id]!, blocks, now),
      ],
    );
  }

  static CategoryProgress _progress(
    Category category,
    List<Block> blocks,
    DateTime now,
  ) {
    var target = 0;
    var expected = 0;
    var actual = 0;
    for (final block in blocks.where((b) => b.categoryId == category.id)) {
      final planned = math.max(0, block.plannedDurationMinutes * 60);
      if (block.status != BlockStatus.cancelled) {
        target += planned;
        final start = block.plannedStart;
        if (start != null) {
          final end = block.plannedEnd ?? start.add(Duration(seconds: planned));
          final until = now.isBefore(end) ? now : end;
          expected += until.difference(start).inSeconds.clamp(0, planned);
        }
      }
      if (block.status == BlockStatus.pending) continue;
      // Count partial work too, including work in a subsequently skipped block.
      var seconds = math.max(0, block.accumulatedSeconds);
      if (block.status == BlockStatus.active && block.runningSince != null) {
        seconds += math.max(0, now.difference(block.runningSince!).inSeconds);
      } else if (seconds == 0 &&
          block.actualStart != null &&
          block.actualEnd != null) {
        seconds = math.max(
          0,
          block.actualEnd!.difference(block.actualStart!).inSeconds,
        );
      }
      actual += seconds;
    }
    return CategoryProgress(
      category: category,
      targetSeconds: target,
      expectedSeconds: expected,
      actualSeconds: actual,
    );
  }

  Map<String, Object?> toJson() => {
    'now': now.toIso8601String(),
    'dayEnd': dayEnd.toIso8601String(),
    'categories': [
      for (final p in categories)
        {
          'id': p.category.id,
          'name': p.category.name,
          'targetSeconds': p.targetSeconds,
          'expectedSeconds': p.expectedSeconds,
          'actualSeconds': p.actualSeconds,
        },
    ],
  };
}
