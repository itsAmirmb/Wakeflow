import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/models/category.dart';
import 'package:wakeflow/models/commitment.dart';
import 'package:wakeflow/models/timeline_entry.dart';
import 'package:wakeflow/services/day_timeline.dart';

final _date = DateTime(2026, 10, 7); // a Wednesday
DateTime _t(int h, [int m = 0]) => DateTime(2026, 10, 7, h, m);

const _academic = Category(
  id: 'a',
  name: 'Academic',
  icon: '📚',
  percentage: 0.5,
  minimumMinutes: 0,
  blockMinutes: 60,
);

Block _block(
  String id,
  String category,
  DateTime start,
  DateTime end, [
  BlockStatus status = BlockStatus.pending,
]) => Block(
  id: id,
  categoryId: category,
  title: id,
  plannedDurationMinutes: end.difference(start).inMinutes,
  plannedStart: start,
  plannedEnd: end,
  status: status,
);

List<TimelineEntry> _build({
  List<Block> blocks = const [],
  List<Commitment> commitments = const [],
  List<int> checkpoints = const [],
  List<DateTime> reviews = const [],
  DateTime? now,
  DateTime? wake,
  DateTime? dayEnd,
  bool showNow = true,
}) => DayTimeline.build(
  date: _date,
  blocks: blocks,
  categories: {'a': _academic},
  commitments: commitments,
  checkpointMinutes: checkpoints,
  reviewTimes: reviews,
  now: now ?? _t(12),
  wake: wake,
  dayEnd: dayEnd,
  showNow: showNow,
);

List<TimelineKind> _kinds(List<TimelineEntry> e) => [for (final x in e) x.kind];

void main() {
  test('everything is in time order with a now marker', () {
    final entries = _build(
      wake: _t(8),
      blocks: [
        _block('b2', 'a', _t(11), _t(12)),
        _block('b1', 'a', _t(9), _t(10), BlockStatus.completed),
      ],
      checkpoints: [14 * 60],
      dayEnd: _t(18),
      now: _t(10, 30),
    );
    expect(_kinds(entries), [
      TimelineKind.wake,
      TimelineKind.block, // b1 09:00
      TimelineKind.breakTime, // 10:00 (gap before b2)
      TimelineKind.now, // 10:30
      TimelineKind.block, // b2 11:00
      TimelineKind.checkpoint, // 14:00
      TimelineKind.dayEnd,
    ]);
  });

  test('cancelled blocks are left out', () {
    final entries = _build(
      blocks: [_block('x', 'a', _t(9), _t(10), BlockStatus.cancelled)],
      showNow: false,
    );
    expect(entries, isEmpty);
  });

  test('a gap between blocks is a break; the last block of a category is '
      'followed by a long break', () {
    final entries = _build(
      showNow: false,
      blocks: [
        _block('a1', 'a', _t(9), _t(10)),
        _block('a2', 'a', _t(10, 10), _t(11, 10)),
        _block('t1', 't', _t(11, 40), _t(12, 40)),
      ],
    );
    final breaks = entries
        .where((e) => e.kind == TimelineKind.breakTime)
        .toList();
    expect(breaks.map((e) => e.title), ['Break', 'Long break']);
    expect(breaks.map((e) => e.detail), ['10 min', '30 min']);
  });

  test('a commitment inside the gap replaces the break', () {
    final entries = _build(
      showNow: false,
      blocks: [
        _block('a1', 'a', _t(9), _t(10)),
        _block('a2', 'a', _t(11), _t(12)),
      ],
      commitments: [
        Commitment(
          id: 'c',
          title: 'Class',
          startMinutes: 10 * 60,
          endMinutes: 11 * 60,
          weekdays: const {DateTime.wednesday},
        ),
      ],
    );
    expect(entries.where((e) => e.kind == TimelineKind.breakTime), isEmpty);
    expect(entries.where((e) => e.kind == TimelineKind.commitment), hasLength(1));
  });

  test('commitments of other weekdays do not appear', () {
    final entries = _build(
      showNow: false,
      commitments: [
        Commitment(
          id: 'c',
          title: 'Gym',
          startMinutes: 600,
          endMinutes: 660,
          weekdays: const {DateTime.monday},
        ),
      ],
    );
    expect(entries, isEmpty);
  });

  group('checkpoints', () {
    CheckpointState? stateAt(List<TimelineEntry> e, int hour) => e
        .firstWhere(
          (x) =>
              x.kind == TimelineKind.checkpoint && x.start == _t(hour),
        )
        .checkpointState;

    final open = [_block('b', 'a', _t(15), _t(16))];

    test('upcoming, due and reviewed', () {
      final entries = _build(
        wake: _t(8),
        dayEnd: _t(20),
        blocks: open,
        checkpoints: [10 * 60, 13 * 60, 17 * 60],
        reviews: [_t(13, 5)],
        now: _t(14),
      );
      expect(stateAt(entries, 10), CheckpointState.due);
      expect(stateAt(entries, 13), CheckpointState.reviewed);
      expect(stateAt(entries, 17), CheckpointState.upcoming);
    });

    test('nothing left to do: a passed, unreviewed checkpoint is missed', () {
      final entries = _build(
        wake: _t(8),
        dayEnd: _t(20),
        blocks: [_block('b', 'a', _t(9), _t(10), BlockStatus.completed)],
        checkpoints: [11 * 60],
        now: _t(14),
      );
      expect(stateAt(entries, 11), CheckpointState.missed);
    });

    test('times outside wake..deadline are ignored', () {
      final entries = _build(
        wake: _t(9),
        dayEnd: _t(18),
        checkpoints: [7 * 60, 19 * 60],
        showNow: false,
      );
      expect(entries.where((e) => e.kind == TimelineKind.checkpoint), isEmpty);
    });

    test('a review that matches no checkpoint is shown as manual', () {
      final entries = _build(
        wake: _t(8),
        dayEnd: _t(20),
        reviews: [_t(16)],
        showNow: false,
      );
      final manual = entries.singleWhere(
        (e) => e.kind == TimelineKind.checkpoint,
      );
      expect(manual.title, 'Checkpoint review');
      expect(manual.checkpointState, CheckpointState.reviewed);
    });
  });
}
