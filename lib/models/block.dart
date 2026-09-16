enum BlockStatus { pending, active, paused, completed, skipped, cancelled }

class Block {
  final String id;
  final String categoryId;
  final String title;
  final int plannedDurationMinutes;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final DateTime? actualStart; // first time this block was ever started
  final DateTime? actualEnd;
  final BlockStatus status;

  /// Total seconds accumulated while active, NOT counting the
  /// currently-running stretch (that part is [runningSince] to now).
  /// Frozen into here every time the block is paused.
  final int accumulatedSeconds;

  /// When the current "active" stretch began. Null when paused,
  /// pending, or finished. Used with [accumulatedSeconds] to compute
  /// elapsed time correctly even if the app was closed and reopened —
  /// nothing depends on an in-memory ticking counter.
  final DateTime? runningSince;

  const Block({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.plannedDurationMinutes,
    this.plannedStart,
    this.plannedEnd,
    this.actualStart,
    this.actualEnd,
    this.status = BlockStatus.pending,
    this.accumulatedSeconds = 0,
    this.runningSince,
  });

  /// Elapsed time as of [now], derived from stored data rather than
  /// any live counter — correct after pause/resume and after the app
  /// has been fully closed and reopened.
  Duration elapsedAt(DateTime now) {
    final running = runningSince == null
        ? Duration.zero
        : now.difference(runningSince!);
    return Duration(seconds: accumulatedSeconds) + running;
  }

  Block copyWith({
    DateTime? plannedStart,
    DateTime? plannedEnd,
    DateTime? actualStart,
    DateTime? actualEnd,
    BlockStatus? status,
    int? accumulatedSeconds,
    // Nullable field: use a sentinel so callers can explicitly clear it
    // (pause) vs. leave it unchanged.
    Object? runningSince = _unset,
  }) {
    return Block(
      id: id,
      categoryId: categoryId,
      title: title,
      plannedDurationMinutes: plannedDurationMinutes,
      plannedStart: plannedStart ?? this.plannedStart,
      plannedEnd: plannedEnd ?? this.plannedEnd,
      actualStart: actualStart ?? this.actualStart,
      actualEnd: actualEnd ?? this.actualEnd,
      status: status ?? this.status,
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
      runningSince: identical(runningSince, _unset)
          ? this.runningSince
          : runningSince as DateTime?,
    );
  }

  @override
  String toString() =>
      'Block($title, ${plannedDurationMinutes}m, $status, start=$plannedStart)';

  // `day` is not a Block field (it's the routine's day, tracked separately
  // by the caller) — it's passed in here only because it lives in the same
  // DB row, so the storage layer needs it alongside the block's own fields.
  Map<String, Object?> toMap({required String day}) {
    return {
      'id': id,
      'day': day,
      'categoryId': categoryId,
      'title': title,
      'plannedDurationMinutes': plannedDurationMinutes,
      'plannedStart': plannedStart?.toIso8601String(),
      'plannedEnd': plannedEnd?.toIso8601String(),
      'actualStart': actualStart?.toIso8601String(),
      'actualEnd': actualEnd?.toIso8601String(),
      'status': status.name,
      'accumulatedSeconds': accumulatedSeconds,
      'runningSince': runningSince?.toIso8601String(),
    };
  }

  factory Block.fromMap(Map<String, Object?> map) {
    return Block(
      id: map['id'] as String,
      categoryId: map['categoryId'] as String,
      title: map['title'] as String,
      plannedDurationMinutes: map['plannedDurationMinutes'] as int,
      plannedStart: map['plannedStart'] == null
          ? null
          : DateTime.parse(map['plannedStart'] as String),
      plannedEnd: map['plannedEnd'] == null
          ? null
          : DateTime.parse(map['plannedEnd'] as String),
      actualStart: map['actualStart'] == null
          ? null
          : DateTime.parse(map['actualStart'] as String),
      actualEnd: map['actualEnd'] == null
          ? null
          : DateTime.parse(map['actualEnd'] as String),
      status: BlockStatus.values.byName(map['status'] as String),
      // Older rows (pre-timer-fix) won't have this column value set;
      // default to 0/null so they just show as freshly paused/pending.
      accumulatedSeconds: map['accumulatedSeconds'] as int? ?? 0,
      runningSince: map['runningSince'] == null
          ? null
          : DateTime.parse(map['runningSince'] as String),
    );
  }
}

const _unset = Object();