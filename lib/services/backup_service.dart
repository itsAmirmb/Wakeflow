import 'dart:convert';

import 'database_service.dart';

/// A backup that cannot be used; [message] is safe to show to the user.
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => message;
}

/// What a backup file contains, shown before anything is replaced.
class BackupSummary {
  final DateTime? exportedAt;
  final int categories;
  final int days;
  final int notes;
  final int commitments;

  const BackupSummary({
    required this.exportedAt,
    required this.categories,
    required this.days,
    required this.notes,
    required this.commitments,
  });
}

typedef BackupTables = Map<String, List<Map<String, Object?>>>;

class ParsedBackup {
  final BackupTables tables;
  final BackupSummary summary;
  const ParsedBackup(this.tables, this.summary);
}

/// Full-backup file format (JSON) and its validation.
///
/// {
///   "app": "wakeflow", "formatVersion": 1, "schemaVersion": 18,
///   "exportedAt": "...", "tables": { "<table>": [ {row}, ... ], ... }
/// }
///
/// Rows are the database rows as they are, so a backup restores exactly,
/// and tables a newer app adds later stay optional for older backups.
class BackupService {
  const BackupService._();

  static const String appId = 'wakeflow';
  static const int formatVersion = 1;

  static String suggestedFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'wakeflow-backup-${now.year}-${two(now.month)}-${two(now.day)}.json';
  }

  /// Pure encoder (the database read is separate, so this is testable).
  static String encode(BackupTables tables, {required DateTime now}) {
    return const JsonEncoder.withIndent('  ').convert({
      'app': appId,
      'formatVersion': formatVersion,
      'schemaVersion': DatabaseService.schemaVersion,
      'exportedAt': now.toIso8601String(),
      'tables': tables,
    });
  }

  static Future<String> export(DatabaseService db, {DateTime? now}) async {
    return encode(await db.exportAllTables(), now: now ?? DateTime.now());
  }

  /// Validates [source] completely before anything is touched; throws a
  /// [BackupException] with a clear reason otherwise.
  static ParsedBackup parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const BackupException('This file is not a WakeFlow backup.');
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != appId) {
      throw const BackupException('This file is not a WakeFlow backup.');
    }
    final version = decoded['formatVersion'];
    if (version is! int || version < 1) {
      throw const BackupException('This backup file is damaged.');
    }
    if (version > formatVersion) {
      throw const BackupException(
        'This backup was made by a newer version of WakeFlow. Update the app '
        'to restore it.',
      );
    }
    final schema = decoded['schemaVersion'];
    if (schema is! int || schema > DatabaseService.schemaVersion) {
      throw const BackupException(
        'This backup was made by a newer version of WakeFlow. Update the app '
        'to restore it.',
      );
    }
    final rawTables = decoded['tables'];
    if (rawTables is! Map<String, dynamic>) {
      throw const BackupException('This backup file is damaged.');
    }

    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in DatabaseService.backupTables) {
      final rows = rawTables[table];
      if (rows is! List) {
        throw BackupException('This backup is incomplete (missing "$table").');
      }
      final parsed = <Map<String, Object?>>[];
      for (final row in rows) {
        if (row is! Map<String, dynamic>) {
          throw const BackupException('This backup file is damaged.');
        }
        for (final value in row.values) {
          // Database values are only ever null, numbers or text.
          if (value != null && value is! num && value is! String) {
            throw const BackupException('This backup file is damaged.');
          }
        }
        parsed.add(Map<String, Object?>.from(row));
      }
      tables[table] = parsed;
    }
    if (tables['categories']!.isEmpty) {
      throw const BackupException('This backup has no categories.');
    }
    if (tables['settings']!.length > 1) {
      throw const BackupException('This backup file is damaged.');
    }

    final exportedAt = decoded['exportedAt'];
    return ParsedBackup(
      tables,
      BackupSummary(
        exportedAt: exportedAt is String ? DateTime.tryParse(exportedAt) : null,
        categories: tables['categories']!.length,
        days: {for (final b in tables['blocks']!) b['day']}.length,
        notes: tables['category_notes']!.length,
        commitments: tables['commitments']!.length,
      ),
    );
  }

  /// Replaces all app data with [backup] in one transaction: either the whole
  /// backup is restored or nothing changes.
  static Future<void> restore(DatabaseService db, ParsedBackup backup) async {
    final tables = {
      for (final entry in backup.tables.entries)
        entry.key: [for (final row in entry.value) Map.of(row)],
    };
    // A chosen phone alarm is a device-specific reference: drop it, the
    // bundled default is used until one is picked again.
    for (final row in tables['settings']!) {
      row['breakAlarmUri'] = null;
      row['breakAlarmTitle'] = null;
    }
    await db.replaceAllTables(tables);
  }
}
