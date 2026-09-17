import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/models/day_mode.dart';
import 'package:wakeflow/screens/today_screen.dart';

VoidCallback callback(WidgetTester tester, String label) => tester
    .widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      ),
    )
    .onPressed!;

void main() {
  testWidgets('outgoing callbacks cannot reset timers or mutate next block', (
    tester,
  ) async {
    final saved = <Block>[];
    final original = List<Block>.unmodifiable([
      const Block(
        id: 'a',
        categoryId: 'c',
        title: 'A',
        plannedDurationMinutes: 30,
      ),
      const Block(
        id: 'b',
        categoryId: 'c',
        title: 'B',
        plannedDurationMinutes: 30,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(
          dayMode: DayMode.normal,
          day: '2026-09-17',
          categories: const [],
          blocks: original,
          persistBlock: (block) async {
            saved.add(block);
          },
        ),
      ),
    );
    final oldStart = callback(tester, 'START');
    oldStart();
    oldStart(); // Double tap before even the first rebuild.
    expect(saved, hasLength(1));
    await tester.pumpAndSettle();
    final oldPause = callback(tester, 'PAUSE');
    oldPause();
    await tester.pumpAndSettle();
    callback(tester, 'RESUME')();
    await tester.pumpAndSettle();
    oldPause(); // Same ID/status again, but a different state snapshot.
    oldStart();
    expect(saved.map((b) => b.status), [
      BlockStatus.active,
      BlockStatus.paused,
      BlockStatus.active,
    ]);
    final oldDone = callback(tester, 'DONE');
    final oldSkip = callback(tester, 'SKIP');
    oldDone();
    await tester.pump(); // Outgoing panel is still animating.
    oldDone();
    oldSkip();
    expect(saved, hasLength(4));
    expect(saved.last.id, 'a');
    expect(saved.last.status, BlockStatus.completed);
    await tester.pumpAndSettle();
    callback(tester, 'START')();
    expect(saved.last.id, 'b');
    expect(original.every((b) => b.status == BlockStatus.pending), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    oldDone(); // Disposed callbacks are harmless too.
    expect(saved, hasLength(5));
  });
}
