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
      version: 5,
      onCreate: (db, version) async {
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

        // Seed categories on first run so the app always has something
        // to allocate time against.
        final batch = db.batch();
        for (final category in defaultCategories) {
          batch.insert('categories', category.toMap());
        }
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
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
        // Older routines did not store their chosen deadline. NULL is
        // intentional: callers use the last persisted planned end as fallback.
        if (oldVersion >= 2 && oldVersion < 5) {
          await db.execute('ALTER TABLE day_meta ADD COLUMN dayEnd TEXT');
        }
      },
    );
  }

  Future<void> _createDayMetaTable(Database db) async {
    // One row per day: the day-mode and wake time a routine was
    // generated with. Needed to resume "today" on app restart
    // without re-asking the user to wake up.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS day_meta (
        day TEXT PRIMARY KEY,
        dayMode TEXT NOT NULL,
        wakeTime TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        id INTEGER PRIMARY KEY,
        bufferMinutes INTEGER NOT NULL,
        wakeReminderHour INTEGER NOT NULL,
        wakeReminderMinute INTEGER NOT NULL,
        themeMode TEXT NOT NULL DEFAULT 'system'
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
