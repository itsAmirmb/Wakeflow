import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/services/note_holder.dart';

Block _b(String id, String category, [BlockStatus status = BlockStatus.pending]) =>
    Block(
      id: id,
      categoryId: category,
      title: id,
      plannedDurationMinutes: 45,
      status: status,
    );

void main() {
  test('notes start on the first block of each category', () {
    final holders = noteHolderBlocks([
      _b('a1', 'a'),
      _b('a2', 'a'),
      _b('t1', 't'),
      _b('t2', 't'),
    ]);
    expect(holders, {'a': 'a1', 't': 't1'});
  });

  test('they move to the next block when the first is finished', () {
    final holders = noteHolderBlocks([
      _b('a1', 'a', BlockStatus.completed),
      _b('a2', 'a'),
      _b('a3', 'a'),
    ]);
    expect(holders['a'], 'a2');
  });

  test('a running or paused block keeps its notes', () {
    expect(
      noteHolderBlocks([_b('a1', 'a', BlockStatus.active), _b('a2', 'a')])['a'],
      'a1',
    );
    expect(
      noteHolderBlocks([_b('a1', 'a', BlockStatus.paused), _b('a2', 'a')])['a'],
      'a1',
    );
  });

  test('skipped and partial blocks count as finished', () {
    final holders = noteHolderBlocks([
      _b('a1', 'a', BlockStatus.skipped),
      _b('a2', 'a', BlockStatus.partial),
      _b('a3', 'a'),
    ]);
    expect(holders['a'], 'a3');
  });

  test('after the last block of a category the notes stay on it', () {
    final holders = noteHolderBlocks([
      _b('a1', 'a', BlockStatus.completed),
      _b('a2', 'a', BlockStatus.completed),
      _b('t1', 't'),
    ]);
    expect(holders['a'], 'a2');
    expect(holders['t'], 't1');
  });

  test('categories move independently', () {
    final holders = noteHolderBlocks([
      _b('a1', 'a', BlockStatus.completed),
      _b('t1', 't'),
      _b('a2', 'a'),
      _b('t2', 't'),
    ]);
    expect(holders, {'a': 'a2', 't': 't1'});
  });
}
