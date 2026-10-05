import '../models/block.dart';

/// The rest between two blocks, derived from saved data only: it starts when
/// the previous block was completed and lasts the configured break length.
/// Nothing extra is stored, so it survives closing and reopening the app.
class BreakState {
  final Block next;
  final DateTime start;
  final DateTime end;

  const BreakState({required this.next, required this.start, required this.end});

  /// How long the "break over" state stays visible after the break ends.
  static const overGrace = Duration(minutes: 15);

  Duration get total => end.difference(start);
  bool isOver(DateTime now) => !now.isBefore(end);
  Duration elapsed(DateTime now) {
    final d = now.difference(start);
    return d.isNegative ? Duration.zero : d;
  }

  static BreakState? derive({
    required List<Block> blocks,
    required int bufferMinutes,
    required DateTime now,
  }) {
    if (bufferMinutes <= 0) return null;
    final index = blocks.indexWhere(
      (b) =>
          b.status == BlockStatus.pending ||
          b.status == BlockStatus.active ||
          b.status == BlockStatus.paused,
    );
    if (index <= 0) return null;
    final next = blocks[index];
    final previous = blocks[index - 1];
    if (next.status != BlockStatus.pending ||
        previous.status != BlockStatus.completed ||
        previous.actualEnd == null) {
      return null;
    }
    final start = previous.actualEnd!;
    final end = start.add(Duration(minutes: bufferMinutes));
    if (now.isBefore(start) || now.isAfter(end.add(overGrace))) return null;
    return BreakState(next: next, start: start, end: end);
  }
}
