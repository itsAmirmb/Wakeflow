import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakeflow/models/app_settings.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/models/category.dart';
import 'package:wakeflow/models/day_mode.dart';
import 'package:wakeflow/screens/checkpoint_history_screen.dart';
import 'package:wakeflow/screens/today_screen.dart';
import 'package:wakeflow/services/database_service.dart';

/// End-to-end checkpoint reviews on TodayScreen over a real SQLite database
/// (sqlite3 FFI) with a fake fixed clock. Every FFI call runs through
/// [WidgetTester.runAsync] so it executes on the real event loop outside the
/// fake async zone; real delays drain pending database work before frames.
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  const day = '2099-01-10';
  const category = Category(
    id: 'work',
    name: 'Work',
    icon: '💡',
    percentage: 1,
    minimumMinutes: 0,
    preferredBlockMinMinutes: 15,
    preferredBlockMaxMinutes: 60,
    priority: 0,
  );

  Block pendingBlock() => Block(
    id: 'b1',
    categoryId: 'work',
    title: 'Deep work',
    plannedDurationMinutes: 60,
    plannedStart: DateTime(2099, 1, 10, 11),
    plannedEnd: DateTime(2099, 1, 10, 12),
  );

  Future<Database> openDb(WidgetTester tester, Directory tempDir) async =>
      (await tester.runAsync(
        () => databaseFactoryFfi.openDatabase(
          '${tempDir.path}${Platform.pathSeparator}today.db',
          options: OpenDatabaseOptions(
            version: 7,
            onCreate: DatabaseService.createSchema,
            onUpgrade: DatabaseService.upgradeSchema,
          ),
        ),
      ))!;

  Future<void> seed(WidgetTester tester, DatabaseService service) async {
    await tester.runAsync(
      () => service.saveDayMeta(
        day: day,
        dayMode: DayMode.normal,
        wakeTime: DateTime(2099, 1, 10, 10),
        dayEnd: DateTime(2099, 1, 10, 18),
      ),
    );
    await tester.runAsync(
      () => service.saveSettings(
        const AppSettings(checkpointMinutesOfDay: [600, 840]),
      ),
    );
    await tester.runAsync(() => service.saveCategory(category));
    await tester.runAsync(
      () => service.saveBlocksForDay(day, [pendingBlock()]),
    );
  }

  /// Lets pending real-zone database futures finish, then flushes the fake
  /// zone's queued microtasks/frame callbacks.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await drain(tester);
    await tester.pumpAndSettle();
  }

  Future<void> pumpToday(
    WidgetTester tester,
    DatabaseService service,
    DateTime Function() now,
    void Function() onSync,
  ) async {
    final blocks =
        (await tester.runAsync(() => service.getBlocksForDay(day)))!;
    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(
          dayMode: DayMode.normal,
          day: day,
          blocks: blocks,
          categories: const [category],
          database: service,
          now: now,
          syncCheckpointReminders: (
            AppSettings settings,
            DateTime wake,
            DateTime end,
          ) async => onSync(),
        ),
      ),
    );
    await settle(tester);
  }

  /// Opens the review sheet, records a Reached assessment, and saves it.
  Future<void> saveReview(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Review checkpoint'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('assessment-work')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reached'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save & continue'));
    await settle(tester);
  }

  testWidgets('two reviews persist and block timers stay untouched', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('wakeflow_today');
    final db = await openDb(tester, tempDir);
    final service = DatabaseService.forTesting(db);
    var now = DateTime(2099, 1, 10, 11);
    var reminderSyncs = 0;
    try {
      await seed(tester, service);
      await pumpToday(tester, service, () => now, () => reminderSyncs++);
      expect(find.text('Saved reviews: 0'), findsOneWidget);
      expect(reminderSyncs, 1);

      await saveReview(tester);
      expect(find.text('Saved reviews: 1'), findsOneWidget);
      expect(reminderSyncs, 2);

      final reviews =
          (await tester.runAsync(() => service.getCheckpoints(day)))!;
      expect(reviews, hasLength(1));
      final blocks =
          (await tester.runAsync(() => service.getBlocksForDay(day)))!;
      final block = blocks.single;
      expect(block.status, BlockStatus.pending);
      expect(block.accumulatedSeconds, 0);
      expect(block.runningSince, isNull);

      now = now.add(const Duration(hours: 2));
      await saveReview(tester);
      expect(find.text('Saved reviews: 2'), findsOneWidget);
      final allReviews = await tester.runAsync(
        () => service.getCheckpoints(day),
      );
      expect(allReviews, hasLength(2));
      expect(reminderSyncs, 3);
    } finally {
      await tester.runAsync(() => db.close());
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets('history tile opens the saved review log', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('wakeflow_today');
    final db = await openDb(tester, tempDir);
    final service = DatabaseService.forTesting(db);
    var now = DateTime(2099, 1, 10, 11);
    try {
      await seed(tester, service);
      await pumpToday(tester, service, () => now, () {});
      await saveReview(tester);
      now = now.add(const Duration(hours: 2));
      await saveReview(tester);
      expect(find.text('Saved reviews: 2'), findsOneWidget);

      await tester.tap(find.text('Saved reviews: 2'));
      await settle(tester);
      expect(find.byType(CheckpointHistoryScreen), findsOneWidget);
      expect(find.text('Reviews · $day'), findsOneWidget);
      expect(find.textContaining('Review at'), findsNWidgets(2));
    } finally {
      await tester.runAsync(() => db.close());
      tempDir.deleteSync(recursive: true);
    }
  });
}
