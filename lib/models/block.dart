enum BlockStatus { pending, active, paused, completed, skipped, cancelled }

class Block {
  final String id;
  final String categoryId;
  final String title;
  final int plannedDurationMinutes;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final BlockStatus status;

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
  });

  Block copyWith({
    DateTime? plannedStart,
    DateTime? plannedEnd,
    DateTime? actualStart,
    DateTime? actualEnd,
    BlockStatus? status,
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
    );
  }
}