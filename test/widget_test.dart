import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/models/category.dart';
import 'package:wakeflow/models/day_mode.dart';
import 'package:wakeflow/screens/home_screen.dart';
import 'package:wakeflow/screens/wake_screen.dart';

void main() {
  testWidgets('Home opens Start Day when no routine exists', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(loadRoutine: (_) async => null)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Day'));
    await tester.pumpAndSettle();
    expect(find.byType(WakeScreen), findsOneWidget);
  });

  testWidgets('Continue clears yesterday cache after midnight', (tester) async {
    var now = DateTime(2026, 9, 17, 23, 59);
    final requested = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          now: () => now,
          loadRoutine: (day) async {
            requested.add(day);
            if (day != '2026-09-17') return null;
            return (
              day: day,
              dayMode: DayMode.normal,
              blocks: [
                const Block(
                  id: 'yesterday',
                  categoryId: 'academic',
                  title: 'Academic',
                  plannedDurationMinutes: 60,
                ),
              ],
              categories: <Category>[],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue Routine'), findsOneWidget);
    now = DateTime(2026, 9, 18, 0, 1);
    await tester.tap(find.text('Continue Routine'));
    await tester.pumpAndSettle();
    expect(requested, ['2026-09-17', '2026-09-18']);
    expect(find.text('Continue Routine'), findsNothing);
    expect(find.text('Start Day'), findsOneWidget);
  });
}
