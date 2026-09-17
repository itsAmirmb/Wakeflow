import 'dart:async';

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
  testWidgets('active restore and rapid actions synchronize in write order', (
    tester,
  ) async {
    final gate = Completer<void>();
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(
          dayMode: DayMode.normal,
          day: '2026-09-17',
          categories: const [],
          blocks: [
            Block(
              id: 'a',
              categoryId: 'c',
              title: 'A',
              plannedDurationMinutes: 30,
              status: BlockStatus.active,
              runningSince: DateTime.now(),
            ),
          ],
          persistBlock: (block) async {
            events.add('write:${block.status.name}');
            if (block.status == BlockStatus.paused) await gate.future;
          },
          syncNotifications: (block) async {
            events.add('notify:${block.status.name}');
          },
        ),
      ),
    );
    expect(events, ['notify:active']);
    callback(tester, 'PAUSE')();
    await tester.pumpAndSettle();
    callback(tester, 'RESUME')();
    await tester.pumpAndSettle();
    expect(events, ['notify:active', 'write:paused']);
    gate.complete();
    await tester.pump();
    expect(events, [
      'notify:active',
      'write:paused',
      'notify:paused',
      'write:active',
      'notify:active',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('notification failure preserves saved progress and is reported', (
    tester,
  ) async {
    final saved = <Block>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(
          dayMode: DayMode.normal,
          day: '2026-09-17',
          categories: const [],
          blocks: const [
            Block(
              id: 'a',
              categoryId: 'c',
              title: 'A',
              plannedDurationMinutes: 30,
            ),
          ],
          persistBlock: (block) async {
            saved.add(block);
          },
          syncNotifications: (_) async {
            throw StateError('denied');
          },
        ),
      ),
    );
    callback(tester, 'START')();
    await tester.pumpAndSettle();
    expect(saved.single.status, BlockStatus.active);
    expect(
      find.text(
        'Could not update block reminders. Check notification permissions.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
          syncNotifications: (_) async {},
        ),
      ),
    );
    final oldStart = callback(tester, 'START');
    oldStart();
    oldStart(); // Double tap before even the first rebuild.
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
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
    await tester.pump();
    expect(saved.last.id, 'b');
    expect(original.every((b) => b.status == BlockStatus.pending), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    oldDone(); // Disposed callbacks are harmless too.
    expect(saved, hasLength(5));
  });
}
