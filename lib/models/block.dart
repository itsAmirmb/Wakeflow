enum BlockStatus { pending, active, paused, completed, skipped, cancelled }

class Block {
  final String id;
  final String categoryId;
  final String title;
  final int plannedDurationMinutes;
  final BlockStatus status;

  const Block({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.plannedDurationMinutes,
    this.status = BlockStatus.pending,
  });

  @override
  String toString() =>
      'Block($title, ${plannedDurationMinutes}m, $status)';
}