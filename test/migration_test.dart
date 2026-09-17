import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakeflow/services/database_service.dart';

/// SQLite close/reopen migration tests. The complete v6 fixture models a real
/// install; historical minimal fixtures exercise only their named columns and
/// deliberately do not claim to reproduce a complete old installation.
void main() {
  sqfliteFfiInit();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wakeflow_migration');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String dbPath(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  /// Builds the supplied fixture, stamps [oldVersion], closes it, and reopens
  /// through the production upgrade hook at the explicit v7 target.
  Future<Database> simulateUpgrade(
    String file,
    Future<void> Function(Database db) createOldSchema, {
    int oldVersion = 4,
  }) async {
    final target = dbPath(file);
    final old = await databaseFactoryFfi.openDatabase(target);
    await createOldSchema(old);
    await old.setVersion(oldVersion);
    await old.close();
    return databaseFactoryFfi.openDatabase(
      target,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: DatabaseService.createSchema,
        onUpgrade: DatabaseService.upgradeSchema,
      ),
    );
  }

  Future<List<String>> columns(Database db, String table) => db
      .rawQuery('PRAGMA table_info($table)')
      .then((rows) => [for (final row in rows) row['name'] as String]);

  test(
    'fresh v7 schema includes checkpoint settings and review storage',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        dbPath('fresh.db'),
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: DatabaseService.createSchema,
        ),
      );
      expect(await db.getVersion(), 7);
      expect(await columns(db, 'day_meta'), contains('dayEnd'));
      expect(await columns(db, 'settings'), contains('checkpointTimes'));
      expect(
        await columns(db, 'checkpoints'),
        containsAll([
          'id',
          'day',
          'reviewedAt',
          'report',
          'assessments',
          'note',
          'recalculated',
        ]),
      );
      await db.insert('settings', {
        'id': 0,
        'bufferMinutes': 10,
        'wakeReminderHour': 8,
        'wakeReminderMinute': 0,
      });
      expect((await db.query('settings')).single['checkpointTimes'], '[]');
      await db.close();
    },
  );

  test(
    'focused v5 release bug (day_meta without dayEnd) migrates on reopen',
    () async {
      final db = await simulateUpgrade('broken.db', (db) async {
        // Focused day_meta column fixture, not a complete shipped schema.
        await db.execute(
          'CREATE TABLE day_meta (day TEXT PRIMARY KEY, dayMode TEXT NOT NULL, wakeTime TEXT NOT NULL)',
        );
      });
      expect(await columns(db, 'day_meta'), contains('dayEnd'));
      // The exact insert from the user's device log now succeeds.
      await db.insert('day_meta', {
        'day': '2026-09-17',
        'dayMode': 'emergency',
        'wakeTime': '2026-09-17T22:20:23.274',
        'dayEnd': '2026-09-18T18:30:00.000',
      });
      await db.close();
    },
  );

  test('complete v6 install preserves data through reopen to v7', () async {
    final db = await simulateUpgrade('complete.db', (db) async {
      await db.execute(
        'CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, icon TEXT NOT NULL, percentage REAL NOT NULL, minimumMinutes INTEGER NOT NULL, preferredBlockMinMinutes INTEGER NOT NULL, preferredBlockMaxMinutes INTEGER NOT NULL, priority INTEGER NOT NULL, enabled INTEGER NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE blocks (id TEXT PRIMARY KEY, day TEXT NOT NULL, categoryId TEXT NOT NULL, title TEXT NOT NULL, plannedDurationMinutes INTEGER NOT NULL, plannedStart TEXT, plannedEnd TEXT, actualStart TEXT, actualEnd TEXT, status TEXT NOT NULL, accumulatedSeconds INTEGER NOT NULL DEFAULT 0, runningSince TEXT)',
      );
      await db.execute('CREATE INDEX idx_blocks_day ON blocks(day)');
      await db.execute(
        'CREATE TABLE day_meta (day TEXT PRIMARY KEY, dayMode TEXT NOT NULL, wakeTime TEXT NOT NULL, dayEnd TEXT)',
      );
      await db.execute(
        "CREATE TABLE settings (id INTEGER PRIMARY KEY, bufferMinutes INTEGER NOT NULL, wakeReminderHour INTEGER NOT NULL, wakeReminderMinute INTEGER NOT NULL, themeMode TEXT NOT NULL DEFAULT 'system')",
      );
      await db.execute("INSERT INTO settings VALUES (0, 15, 7, 30, 'dark')");
      await db.execute(
        "INSERT INTO blocks VALUES ('b1', '2099-01-10', 'work', 'Work', 30, '2099-01-10T10:00:00.000', '2099-01-10T10:30:00.000', '2099-01-10T10:00:00.000', '2099-01-10T10:20:00.000', 'completed', 1200, NULL)",
      );
    });
    expect(await columns(db, 'settings'), contains('checkpointTimes'));
    expect((await db.query('settings')).single['checkpointTimes'], '[]');
    expect(
      (await db.query('blocks', where: "id = 'b1'")).single['actualEnd'],
      '2099-01-10T10:20:00.000',
    );
    expect(await columns(db, 'checkpoints'), contains('recalculated'));
    await db.close();
  });

  test('focused legacy v1 install gains dayEnd and timer columns', () async {
    final db = await simulateUpgrade('legacy.db', (db) async {
      await db.execute(
        'CREATE TABLE day_meta (day TEXT PRIMARY KEY, dayMode TEXT NOT NULL, wakeTime TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE blocks (id TEXT PRIMARY KEY, day TEXT, categoryId TEXT, title TEXT, plannedDurationMinutes INTEGER, plannedStart TEXT, plannedEnd TEXT, actualStart TEXT, actualEnd TEXT, status TEXT)',
      );
    }, oldVersion: 1);
    expect(await columns(db, 'day_meta'), contains('dayEnd'));
    expect(
      await columns(db, 'blocks'),
      containsAll(['accumulatedSeconds', 'runningSince']),
    );
    await db.close();
  });

  test('rerunning upgradeSchema is idempotent', () async {
    final db = await simulateUpgrade('idem.db', (db) async {
      await db.execute(
        'CREATE TABLE day_meta (day TEXT PRIMARY KEY, dayMode TEXT NOT NULL, wakeTime TEXT NOT NULL)',
      );
    });
    await DatabaseService.upgradeSchema(db, 5, 6);
    final dayEndCount = (await db.rawQuery('PRAGMA table_info(day_meta)'))
        .where((row) => row['name'] == 'dayEnd')
        .length;
    expect(dayEndCount, 1);
    await db.close();
  });
}
