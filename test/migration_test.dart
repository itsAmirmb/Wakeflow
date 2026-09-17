import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakeflow/services/database_service.dart';

/// Migration tests run against a real SQLite engine (sqlite3 FFI), so
/// ALTER/PRAGMA behavior matches the sqflite Android path. Each test
/// reproduces an actual device history by creating the DB with the OLD
/// release's schema, stamping its version, closing it, and reopening
/// with the NEW openDatabase hooks — the same close/reopen path a
/// device upgrade takes.
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

  /// Builds the old database exactly as the old release created it,
  /// stamps [stampedVersion] on it, then reopens it at [version] using
  /// the new schema hooks.
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
        version: oldVersion + 2, // forces onUpgrade(oldVersion, ...)
        onCreate: DatabaseService.createSchema,
        onUpgrade: DatabaseService.upgradeSchema,
      ),
    );
  }

  Future<List<String>> columns(Database db, String table) => db
      .rawQuery('PRAGMA table_info($table)')
      .then((rows) => [for (final row in rows) row['name'] as String]);

  test('fresh install: createSchema includes dayEnd', () async {
    final db = await databaseFactoryFfi.openDatabase(
      dbPath('fresh.db'),
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: DatabaseService.createSchema,
      ),
    );
    expect(await columns(db, 'day_meta'), contains('dayEnd'));
    await db.close();
  });

  test('v5 release bug (day_meta without dayEnd) migrates on reopen', () async {
    final db = await simulateUpgrade('broken.db', (db) async {
      // Exactly what the shipped v0.12.3 onCreate built.
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
  });

  test('legacy v1 install gains dayEnd and timer columns', () async {
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
