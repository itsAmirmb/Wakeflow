import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/services/day_label.dart';

void main() {
  const today = '2026-10-07'; // a Wednesday

  test('today and yesterday are named', () {
    expect(formatDayLabel('2026-10-07', today: today), 'Today');
    expect(formatDayLabel('2026-10-06', today: today), 'Yesterday');
  });

  test('older days show weekday and date', () {
    expect(formatDayLabel('2026-10-05', today: today), 'Mon, Oct 5');
  });

  test('another year includes the year', () {
    expect(formatDayLabel('2025-12-31', today: today), 'Wed, Dec 31, 2025');
  });

  test('yesterday works across a month boundary', () {
    expect(formatDayLabel('2026-09-30', today: '2026-10-01'), 'Yesterday');
  });
}
