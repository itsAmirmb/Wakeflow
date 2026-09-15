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
}