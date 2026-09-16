import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/block.dart';
import '../models/category.dart';
import '../models/day_mode.dart';
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
      version: 2,
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
  }) async {
    final db = await database;
    await db.insert(
      'day_meta',
      {
        'day': day,
        'dayMode': dayMode.name,
        'wakeTime': wakeTime.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns (dayMode, wakeTime) for [day], or null if no routine has
  /// been generated for that day yet.
  Future<(DayMode, DateTime)?> getDayMeta(String day) async {
    final db = await database;
    final rows = await db.query('day_meta', where: 'day = ?', whereArgs: [day]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (
      DayMode.values.byName(row['dayMode'] as String),
      DateTime.parse(row['wakeTime'] as String),
    );
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
}
