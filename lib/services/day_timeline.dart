import '../models/block.dart';
import '../models/category.dart';
import '../models/commitment.dart';
import '../models/timeline_entry.dart';

/// Builds the day timeline from the day's data. Pure: the same inputs always
/// give the same rows, so it can be recomputed every few seconds to move the
/// "now" marker and is easy to test.
class DayTimeline {
  const DayTimeline._();

  static String clock(DateTime t) =>
      Commitment.hm(t.hour * 60 + t.minute);

  static String dayKeyOf(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  static bool _unfinished(Block b) =>
      b.status == BlockStatus.pending ||
      b.status == BlockStatus.active ||
      b.status == BlockStatus.paused;

  static List<TimelineEntry> build({
    required DateTime date,
    required List<Block> blocks,
    required Map<String, Category> categories,
    required List<Commitment> commitments,
    required List<int> checkpointMinutes,
    required List<DateTime> reviewTimes,
    required DateTime now,
    DateTime? wake,
    DateTime? dayEnd,
    bool showNow = true,
  }) {
    final day = DateTime(date.year, date.month, date.day);
    final entries = <TimelineEntry>[];

    // Blocks that are part of the day and have a place on the clock.
    final timed =
        blocks
            .where(
              (b) =>
                  b.status != BlockStatus.cancelled &&
                  (b.plannedStart ?? b.actualStart) != null,
            )
            .toList()
          ..sort(
            (a, b) => (a.plannedStart ?? a.actualStart!).compareTo(
              b.plannedStart ?? b.actualStart!,
            ),
          );
    final hasUnfinished = timed.any(_unfinished);

    if (wake != null) {
      entries.add(
        TimelineEntry(kind: TimelineKind.wake, start: wake, title: 'Woke up'),
      );
    }

    for (final block in timed) {
      final seconds = block.recordedSeconds;
      entries.add(
        TimelineEntry(
          kind: TimelineKind.block,
          start: block.plannedStart ?? block.actualStart!,
          end: block.plannedEnd ?? block.actualEnd,
          title: block.title,
          icon: categories[block.categoryId]?.icon,
          blockStatus: block.status,
          detail: seconds >= 60
              ? '${block.plannedDurationMinutes} min planned · '
                    '${seconds ~/ 60} min on timer'
              : '${block.plannedDurationMinutes} min planned',
        ),
      );
    }

    // The routine may run past midnight: fixed events of the following
    // days belong in it too.
    var spanEnd = dayEnd ?? DateTime(day.year, day.month, day.day + 1);
    for (final b in timed) {
      final end = b.plannedEnd ?? b.actualEnd;
      if (end != null && end.isAfter(spanEnd)) spanEnd = end;
    }
    final busy = <BusyInterval>[];
    for (final slot in Commitment.slotsBetween(commitments, day, spanEnd)) {
      busy.add(slot.interval);
      entries.add(
        TimelineEntry(
          kind: TimelineKind.commitment,
          start: slot.interval.start,
          end: slot.interval.end,
          title: slot.commitment.title,
          detail: 'Fixed commitment',
        ),
      );
    }

    // Breaks: the planned gap between two blocks, unless a commitment fills
    // it. The gap after a category's last block is its long break.
    for (var i = 0; i + 1 < timed.length; i++) {
      final a = timed[i];
      final b = timed[i + 1];
      final gapStart = a.plannedEnd ?? a.actualEnd;
      final gapEnd = b.plannedStart ?? b.actualStart;
      if (gapStart == null || gapEnd == null) continue;
      final minutes = gapEnd.difference(gapStart).inMinutes;
      if (minutes < 1) continue;
      final filled = busy.any(
        (iv) => iv.start.isBefore(gapEnd) && iv.end.isAfter(gapStart),
      );
      if (filled) continue;
      final isLong = !timed
          .skip(i + 1)
          .any((x) => x.categoryId == a.categoryId);
      entries.add(
        TimelineEntry(
          kind: TimelineKind.breakTime,
          start: gapStart,
          end: gapEnd,
          title: isLong ? 'Long break' : 'Break',
          detail: '$minutes min',
        ),
      );
    }

    _addCheckpoints(
      entries,
      day: day,
      minutesOfDay: checkpointMinutes,
      reviewTimes: reviewTimes,
      now: now,
      wake: wake,
      dayEnd: dayEnd,
      hasUnfinished: hasUnfinished,
    );

    if (dayEnd != null) {
      entries.add(
        TimelineEntry(
          kind: TimelineKind.dayEnd,
          start: dayEnd,
          title: 'Day target',
        ),
      );
    }

    entries.sort((a, b) {
      final byTime = a.start.compareTo(b.start);
      if (byTime != 0) return byTime;
      final byKind = a.order.compareTo(b.order);
      return byKind != 0 ? byKind : a.title.compareTo(b.title);
    });

    if (showNow) {
      // After everything that has already started.
      var index = entries.indexWhere((e) => e.start.isAfter(now));
      if (index == -1) index = entries.length;
      entries.insert(
        index,
        TimelineEntry(kind: TimelineKind.now, start: now, title: 'Now'),
      );
    }
    return entries;
  }

  /// Same rule as the checkpoint gate: configured times between wake time
  /// and the deadline. Each is matched with the first review saved at or
  /// after it (and before the next one); other reviews are shown as manual.
  static void _addCheckpoints(
    List<TimelineEntry> entries, {
    required DateTime day,
    required List<int> minutesOfDay,
    required List<DateTime> reviewTimes,
    required DateTime now,
    required DateTime? wake,
    required DateTime? dayEnd,
    required bool hasUnfinished,
  }) {
    final from = wake ?? day;
    final limit = dayEnd ?? DateTime(day.year, day.month, day.day + 1);
    final times = <DateTime>[];
    for (
      var d = day;
      !d.isAfter(limit);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      for (final minute in minutesOfDay) {
        final when = DateTime(d.year, d.month, d.day, minute ~/ 60, minute % 60);
        if (!when.isBefore(from) && when.isBefore(limit)) times.add(when);
      }
    }
    times.sort();

    final remaining = [...reviewTimes]..sort();
    for (var i = 0; i < times.length; i++) {
      final due = times[i];
      final next = i + 1 < times.length ? times[i + 1] : null;
      final index = remaining.indexWhere(
        (r) => !r.isBefore(due) && (next == null || r.isBefore(next)),
      );
      final CheckpointState state;
      String? detail;
      if (index != -1) {
        state = CheckpointState.reviewed;
        detail = 'Reviewed at ${clock(remaining.removeAt(index))}';
      } else if (now.isBefore(due)) {
        state = CheckpointState.upcoming;
      } else if (hasUnfinished) {
        state = CheckpointState.due;
        detail = 'Review it now';
      } else {
        state = CheckpointState.missed;
        detail = 'Not reviewed';
      }
      entries.add(
        TimelineEntry(
          kind: TimelineKind.checkpoint,
          start: due,
          title: 'Checkpoint',
          detail: detail,
          checkpointState: state,
        ),
      );
    }

    for (final review in remaining) {
      entries.add(
        TimelineEntry(
          kind: TimelineKind.checkpoint,
          start: review,
          title: 'Checkpoint review',
          detail: 'Started manually',
          checkpointState: CheckpointState.reviewed,
        ),
      );
    }
  }
}
