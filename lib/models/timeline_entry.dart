import 'block.dart';

enum TimelineKind { wake, checkpoint, commitment, block, breakTime, dayEnd, now }

/// Where a checkpoint stands.
enum CheckpointState {
  /// A review was saved for it.
  reviewed,

  /// Its time has passed, no review yet, and work is still left.
  due,

  /// Still ahead.
  upcoming,

  /// Its time passed without a review and nothing is left to review.
  missed,
}

/// One row of the day timeline. Presentation (icons, colours) is decided by
/// the screen; this only says what happens when.
class TimelineEntry {
  final TimelineKind kind;
  final DateTime start;

  /// Null for single moments (wake, checkpoint, day target, now).
  final DateTime? end;
  final String title;
  final String? detail;

  /// Category emoji for blocks.
  final String? icon;
  final BlockStatus? blockStatus;
  final CheckpointState? checkpointState;

  const TimelineEntry({
    required this.kind,
    required this.start,
    required this.title,
    this.end,
    this.detail,
    this.icon,
    this.blockStatus,
    this.checkpointState,
  });

  /// Tie-break for entries that start at the same minute.
  int get order => switch (kind) {
    TimelineKind.wake => 0,
    TimelineKind.checkpoint => 1,
    TimelineKind.commitment => 2,
    TimelineKind.block => 3,
    TimelineKind.breakTime => 4,
    TimelineKind.dayEnd => 5,
    TimelineKind.now => 6,
  };
}
