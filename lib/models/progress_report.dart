import 'dart:math' as math;

import '../services/routine_engine.dart';
import 'block.dart';
import 'category.dart';
import 'checkpoint_report.dart';

class CategoryReport {
  final Category category;

  /// Planned for the day before distilling (discarded blocks included).
  final int targetSeconds;

  /// What the plan expected to be done by the checkpoint.
  final int expectedSeconds;

  /// Real timer time in the blocks that survived the distillation.
  final int realSeconds;
  final int completedBlocks;
  final int partialBlocks;
  final CheckpointAssessment? assessment;

  const CategoryReport({
    required this.category,
    required this.targetSeconds,
    required this.expectedSeconds,
    required this.realSeconds,
    required this.completedBlocks,
    required this.partialBlocks,
    required this.assessment,
  });

  int get targetMinutes => targetSeconds ~/ 60;
  int get expectedMinutes => expectedSeconds ~/ 60;
  int get realMinutes => realSeconds ~/ 60;
}

/// Progress of today right after a checkpoint distillation: what really
/// happened (recorded timer time only), measured against what was planned.
/// Like [CheckpointReport], it is evidence for reflection, not proof of
/// task completion.
class ProgressReport {
  final DateTime now;
  final DateTime dayEnd;
  final List<CategoryReport> categories;
  final int discardedBlocks;
  final int discardedPlannedMinutes;
  final String note;

  const ProgressReport({
    required this.now,
    required this.dayEnd,
    required this.categories,
    required this.discardedBlocks,
    required this.discardedPlannedMinutes,
    required this.note,
  });

  int get realSeconds => categories.fold(0, (s, c) => s + c.realSeconds);
  int get targetSeconds => categories.fold(0, (s, c) => s + c.targetSeconds);
  int get expectedSeconds =>
      categories.fold(0, (s, c) => s + c.expectedSeconds);
  int get completedBlocks =>
      categories.fold(0, (s, c) => s + c.completedBlocks);
  int get partialBlocks => categories.fold(0, (s, c) => s + c.partialBlocks);
  int get remainingMinutes => math.max(0, dayEnd.difference(now).inMinutes);

  /// [before] is the day's plan at the checkpoint (it supplies target and
  /// scheduled-by-now); real work comes only from [result], the distilled
  /// blocks, so discarded progress is never counted.
  factory ProgressReport.build({
    required List<Block> before,
    required DistillResult result,
    required List<Category> categories,
    required DateTime now,
    required DateTime dayEnd,
    required Map<String, CheckpointAssessment> assessments,
    required String note,
  }) {
    final snapshot = CheckpointReport.fromBlocks(
      blocks: before,
      categories: categories,
      now: now,
      dayEnd: dayEnd,
    );
    CategoryReport forCategory(CategoryProgress p) {
      final mine = result.blocks.where((b) => b.categoryId == p.category.id);
      return CategoryReport(
        category: p.category,
        targetSeconds: p.targetSeconds,
        expectedSeconds: p.expectedSeconds,
        realSeconds: mine.fold<int>(0, (s, b) => s + b.recordedSeconds),
        completedBlocks: mine
            .where((b) => b.status == BlockStatus.completed)
            .length,
        partialBlocks: mine.where((b) => b.status == BlockStatus.partial).length,
        assessment: assessments[p.category.id],
      );
    }

    return ProgressReport(
      now: now,
      dayEnd: dayEnd,
      categories: [for (final p in snapshot.categories) forCategory(p)],
      discardedBlocks: result.discarded.length,
      discardedPlannedMinutes: result.discardedPlannedMinutes,
      note: note,
    );
  }

  /// Compact summary stored with the checkpoint so history can show it.
  Map<String, Object?> toJson() => {
    'realSeconds': {for (final c in categories) c.category.id: c.realSeconds},
    'completedBlocks': completedBlocks,
    'partialBlocks': partialBlocks,
    'discardedBlocks': discardedBlocks,
    'discardedPlannedMinutes': discardedPlannedMinutes,
  };
}
