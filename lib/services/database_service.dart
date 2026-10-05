import 'dart:convert';

import '../models/checkpoint_report.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/block.dart';
import '../models/category.dart';
import '../models/day_mode.dart';
import '../models/app_settings.dart';
import '../data/default_categories.dart';

/// Thin wrapper around a single sqflite database.
///
/// Two tables:
/// - `categories`: the user's category config (seeded from
///   [defaultCategories] the first time the app runs).
/// - `blocks`: every block ever generated, tagged with the `day`
///   (yyyy-MM-dd) it belongs to. "Today" = blocks where day == today.
///   "History" = every other day's blocks, grouped by day.
class DatabaseService {
  DatabaseService._internal();

  @visibleForTesting
  DatabaseService.forTesting(Database database) : _db = database;
  static final DatabaseService instance = DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'wakeflow.db');

    return openDatabase(
      path,
      version: 10,
      onCreate: createSchema,
      onUpgrade: upgradeSchema,
    );
  }

  /// Adds [column] to [table] only when the table exists and lacks it.
  ///
  /// Schema changes used to live only in `onUpgrade`, so an install that
  /// already reached the newest version number without the column (the
  /// v5 release bug: fresh installs created `day_meta` without `dayEnd`)
  /// never converged. Checking `PRAGMA table_info` makes every path —
  /// fresh create, any historical upgrade path, or a DB stamped with a
  /// newer version than its columns — end up with the same schema.
  /// A missing table is skipped: CREATE TABLE hooks own whole tables.
  @visibleForTesting
  static Future<void> ensureColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (info.isEmpty || info.any((row) => row['name'] == column)) {
      return;
    }
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  /// Full schema for a fresh install. Also reused by [upgradeSchema] when
  /// an old install is missing whole tables.
  @visibleForTesting
  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        percentage REAL NOT NULL,
        minimumMinutes INTEGER NOT NULL,
        preferredBlockMinMinutes INTEGER NOT NULL,
        preferredBlockMaxMinutes INTEGER NOT NULL,
        priority INTEGER NOT NULL,
        enabled INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE blocks (
        id TEXT PRIMARY KEY,
        day TEXT NOT NULL,
        categoryId TEXT NOT NULL,
        title TEXT NOT NULL,
        plannedDurationMinutes INTEGER NOT NULL,
        plannedStart TEXT,
        plannedEnd TEXT,
        actualStart TEXT,
        actualEnd TEXT,
        status TEXT NOT NULL,
        accumulatedSeconds INTEGER NOT NULL DEFAULT 0,
        runningSince TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_blocks_day ON blocks(day)');

    await _createDayMetaTable(db);
    await _createSettingsTable(db);
    await _createCheckpointsTable(db);

    // Seed categories on first run so the app always has something
    // to allocate time against.
    final batch = db.batch();
    for (final category in defaultCategories) {
      batch.insert('categories', category.toMap());
    }
    await batch.commit(noResult: true);
  }

  @visibleForTesting
  static Future<void> upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // v1 -> v2: added day_meta (needed to resume today's routine
    // after the app is killed). Older installs already have
    // categories/blocks from v1, so only add what's missing.
    if (oldVersion < 2) {
      await _createDayMetaTable(db);
    }
    // v2 -> v3: added settings (buffer minutes, wake reminder time).
    if (oldVersion < 3) {
      await _createSettingsTable(db);
    }
    // v3 -> v4: added themeMode to settings (light/dark/system).
    if (oldVersion < 4) {
      // settings table won't exist yet if upgrading straight from
      // v1/v2 in the same run — _createSettingsTable already
      // includes themeMode for that case, so only ALTER when the
      // table was already there.
      if (oldVersion >= 3) {
        await db.execute(
          "ALTER TABLE settings ADD COLUMN themeMode TEXT NOT NULL DEFAULT 'system'",
        );
      }
    }
    // v4 -> v5: routines now store their chosen deadline. NULL is
    // intentional for rows written before this existed: callers use
    // the last persisted planned end as fallback.
    //
    // v5 -> v6: the v5 release created day_meta WITHOUT dayEnd on fresh
    // installs (onCreate never ran the ALTER), crashing Generate with
    // "no column named dayEnd". Version 6 re-runs the migration on those
    // devices. ensureColumn also reconciles columns a pre-0.9.1 v1
    // install never received (timer columns on blocks). The guards are
    // unconditional: every ensureColumn call is a no-op when its table
    // or column is already correct, and _createDayMetaTable uses
    // IF NOT EXISTS.
    if (oldVersion < 6) {
      await ensureColumn(db, 'day_meta', 'dayEnd', 'TEXT');
      await ensureColumn(
        db,
        'blocks',
        'accumulatedSeconds',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await ensureColumn(db, 'blocks', 'runningSince', 'TEXT');
    }
    if (oldVersion < 7) {
      await ensureColumn(db, 'settings', 'checkpointTimes', "TEXT NOT NULL DEFAULT '[]'");
      await _createCheckpointsTable(db);
    }
    // v8 -> v9: distillation keep-threshold (columns are idempotent, so any
    // earlier path converges on the same schema).
    if (oldVersion < 9) {
      await ensureColumn(
        db,
        'settings',
        'distillKeepMode',
        "TEXT NOT NULL DEFAULT 'minutes'",
      );
      await ensureColumn(
        db,
        'settings',
        'distillKeepValue',
        'INTEGER NOT NULL DEFAULT 5',
      );
    }
    // v9 -> v10: configurable day-reset time (default 04:00).
    if (oldVersion < 10) {
      await ensureColumn(
        db,
        'settings',
        'dayResetMinutes',
        'INTEGER NOT NULL DEFAULT 240',
      );
    }
  }

  static Future<void> _createCheckpointsTable(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS checkpoints (
      id TEXT PRIMARY KEY, day TEXT NOT NULL, reviewedAt TEXT NOT NULL,
      report TEXT NOT NULL, assessments TEXT NOT NULL, note TEXT NOT NULL,
      recalculated INTEGER NOT NULL
    )''');
  }

  /// Reflection and optional future replacement commit together.
  Future<void> saveCheckpoint({
    required String id, required String day, required CheckpointReport report,
    required Map<String, CheckpointAssessment> assessments,
    required String note, List<Block>? proposed,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('checkpoints', {
        'id': id, 'day': day, 'reviewedAt': report.now.toIso8601String(),
        'report': jsonEncode(report.toJson()),
        'assessments': jsonEncode(assessments.map((k, v) => MapEntry(k, v.name))),
        'note': note, 'recalculated': proposed == null ? 0 : 1,
      });
      if (proposed != null) {
        await txn.delete('blocks', where: 'day = ?', whereArgs: [day]);
        for (final block in proposed) {
          await txn.insert('blocks', block.toMap(day: day));
        }
      }
    });
  }

  Future<List<Map<String, Object?>>> getCheckpoints(String day) async {
    final db = await database;
    return db.query('checkpoints', where: 'day = ?', whereArgs: [day], orderBy: 'reviewedAt DESC');
  }

  static Future<void> _createDayMetaTable(Database db) async {
    // One row per day: the day-mode and wake time a routine was
    // generated with. Needed to resume "today" on app restart
    // without re-asking the user to wake up. dayEnd is part of the
    // CREATE now — a fresh v6 install must not depend on onUpgrade
    // to add it (that was the v5 release bug).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS day_meta (
        day TEXT PRIMARY KEY,
        dayMode TEXT NOT NULL,
        wakeTime TEXT NOT NULL,
        dayEnd TEXT
      )
    ''');
  }

  static Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        id INTEGER PRIMARY KEY,
        bufferMinutes INTEGER NOT NULL,
        wakeReminderHour INTEGER NOT NULL,
        wakeReminderMinute INTEGER NOT NULL,
        themeMode TEXT NOT NULL DEFAULT 'system',
        checkpointTimes TEXT NOT NULL DEFAULT '[]',
        distillKeepMode TEXT NOT NULL DEFAULT 'minutes',
        distillKeepValue INTEGER NOT NULL DEFAULT 5,
        dayResetMinutes INTEGER NOT NULL DEFAULT 240
      )
    ''');
  }

  // ---------- Categories ----------

  Future<List<Category>> getCategories() async {
    final db = await database;
    final rows = await db.query('categories', orderBy: 'priority ASC');
    return rows.map(Category.fromMap).toList();
  }

  Future<void> saveCategory(Category category) async {
    final db = await database;
    await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Saves several categories atomically (used when Start Day persists the
  /// edited order, enabled flags and sliders in one go).
  Future<void> saveCategories(List<Category> categories) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final category in categories) {
        batch.insert(
          'categories',
          category.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Alias kept explicit for Settings-screen call sites — same
  /// insert-or-replace as saveCategory, used when editing an existing
  /// category rather than seeding a new one.
  Future<void> updateCategory(Category category) => saveCategory(category);

  // ---------- Blocks ----------

  /// Replaces all blocks for [day] with [blocks]. Used when a fresh
  /// routine is generated (day-mode screen) or when a checkpoint
  /// recalculates the remaining day.
  Future<void> saveBlocksForDay(String day, List<Block> blocks) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('blocks', where: 'day = ?', whereArgs: [day]);
      final batch = txn.batch();
      for (final block in blocks) {
        batch.insert('blocks', block.toMap(day: day));
      }
      await batch.commit(noResult: true);
    });
  }

  /// Updates a single block's row in place (used for START/PAUSE/
  /// COMPLETE/SKIP, so we don't touch the other blocks in the day).
  Future<void> updateBlock(String day, Block block) async {
    final db = await database;
    await db.update(
      'blocks',
      block.toMap(day: day),
      where: 'id = ?',
      whereArgs: [block.id],
    );
  }

  Future<List<Block>> getBlocksForDay(String day) async {
    final db = await database;
    final rows = await db.query(
      'blocks',
      where: 'day = ?',
      whereArgs: [day],
      orderBy: 'plannedStart ASC',
    );
    return rows.map(Block.fromMap).toList();
  }

  // ---------- Day meta (dayMode + wakeTime per day) ----------

  Future<void> saveDayMeta({
    required String day,
    required DayMode dayMode,
    required DateTime wakeTime,
    DateTime? dayEnd,
  }) async {
    final db = await database;
    await db.insert('day_meta', {
      'day': day,
      'dayMode': dayMode.name,
      'wakeTime': wakeTime.toIso8601String(),
      'dayEnd': dayEnd?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns (dayMode, wakeTime, dayEnd) for [day], or null if no routine
  /// has been generated for that day yet. [dayEnd] is null for routines
  /// created before the deadline was persisted (schema v5).
  Future<(DayMode, DateTime, DateTime?)?> getDayMeta(String day) async {
    final db = await database;
    final rows = await db.query('day_meta', where: 'day = ?', whereArgs: [day]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (
      DayMode.values.byName(row['dayMode'] as String),
      DateTime.parse(row['wakeTime'] as String),
      row['dayEnd'] == null ? null : DateTime.parse(row['dayEnd'] as String),
    );
  }

  /// Writes a day's metadata and its blocks atomically. Either both land
  /// or neither does, so a crash mid-generation can never leave a day
  /// resumable with no blocks (or blocks with no meta).
  Future<void> saveDayRoutine({
    required String day,
    required DayMode dayMode,
    required DateTime wakeTime,
    DateTime? dayEnd,
    required List<Block> blocks,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('day_meta', {
        'day': day,
        'dayMode': dayMode.name,
        'wakeTime': wakeTime.toIso8601String(),
        'dayEnd': dayEnd?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('blocks', where: 'day = ?', whereArgs: [day]);
      final batch = txn.batch();
      for (final block in blocks) {
        batch.insert('blocks', block.toMap(day: day));
      }
      await batch.commit(noResult: true);
    });
  }

  /// Most recent day before [beforeDay] that still has blocks waiting to run
  /// (pending, active or paused). Such a routine carries over past the day
  /// reset time until it is finished or distilled.
  Future<String?> latestUnfinishedDayBefore(String beforeDay) async {
    final db = await database;
    final rows = await db.query(
      'blocks',
      columns: ['DISTINCT day'],
      where: "day < ? AND status IN ('pending', 'active', 'paused')",
      whereArgs: [beforeDay],
      orderBy: 'day DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['day'] as String;
  }

  /// All distinct days that have blocks, excluding [today] — this is
  /// the simple "history" list (no separate history table needed).
  Future<List<String>> getHistoryDays(String today) async {
    final db = await database;
    final rows = await db.query(
      'blocks',
      columns: ['DISTINCT day'],
      where: 'day != ?',
      whereArgs: [today],
      orderBy: 'day DESC',
    );
    return rows.map((r) => r['day'] as String).toList();
  }

  // ---------- Settings ----------

  Future<AppSettings> getSettings() async {
    final db = await database;
    final rows = await db.query('settings', where: 'id = 0');
    if (rows.isEmpty) {
      // No row yet (first run) — return defaults without writing,
      // saveSettings() will create the row the first time the user
      // actually changes something.
      return const AppSettings();
    }
    return AppSettings.fromMap(rows.first);
  }

  Future<void> saveSettings(AppSettings settings) async {
    final db = await database;
    await db.insert(
      'settings',
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
