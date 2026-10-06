import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/category.dart';
import 'package:wakeflow/services/routine_engine.dart';

Category _category(int blockMinutes) => Category(
  id: 'c',
  name: 'C',
  icon: 'x',
  percentage: 1,
  minimumMinutes: 0,
  blockMinutes: blockMinutes,
);

List<int> _split(int blockMinutes, int minutes) => RoutineEngine
    .splitIntoBlocks(
      categories: [_category(blockMinutes)],
      allocation: {'c': minutes},
    )
    .map((b) => b.plannedDurationMinutes)
    .toList();

void main() {
  test('time divides into fixed-size blocks', () {
    expect(_split(45, 90), [45, 45]);
  });

  test('a leftover shorter than a block joins the last block', () {
    expect(_split(45, 100), [45, 55]);
    expect(_split(45, 134), [45, 89]);
    expect(_split(60, 200), [60, 60, 80]);
  });

  test('time shorter than one block is a single short block', () {
    expect(_split(45, 30), [30]);
  });

  test('no time means no blocks', () {
    expect(_split(45, 0), isEmpty);
  });
}
