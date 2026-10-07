import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/services/backup_service.dart';
import 'package:wakeflow/services/database_service.dart';

BackupTables _tables() => {
  for (final t in DatabaseService.backupTables) t: <Map<String, Object?>>[],
}
  ..['categories'] = [
    {'id': 'academic', 'name': 'Academic', 'percentage': 0.4, 'enabled': 1},
  ]
  ..['blocks'] = [
    {'id': 'b1', 'day': '2026-10-05', 'title': 'Read', 'plannedDurationMinutes': 60},
    {'id': 'b2', 'day': '2026-10-05', 'title': 'Code', 'plannedDurationMinutes': 45},
    {'id': 'b3', 'day': '2026-10-06', 'title': 'Read', 'plannedDurationMinutes': 60},
  ]
  ..['category_notes'] = [
    {'id': 'n1', 'categoryId': 'academic', 'text': 'Chapter 3'},
  ];

String _encoded() => BackupService.encode(_tables(), now: DateTime(2026, 10, 7, 9));

void main() {
  test('a backup round-trips exactly', () {
    final parsed = BackupService.parse(_encoded());
    expect(parsed.tables['categories'], _tables()['categories']);
    expect(parsed.tables['blocks'], _tables()['blocks']);
    expect(parsed.summary.categories, 1);
    expect(parsed.summary.days, 2);
    expect(parsed.summary.notes, 1);
    expect(parsed.summary.commitments, 0);
    expect(parsed.summary.exportedAt, DateTime(2026, 10, 7, 9));
  });

  test('file name carries the date', () {
    expect(
      BackupService.suggestedFileName(DateTime(2026, 10, 7)),
      'wakeflow-backup-2026-10-07.json',
    );
  });

  test('rejects things that are not a WakeFlow backup', () {
    expect(() => BackupService.parse('not json'), throwsA(isA<BackupException>()));
    expect(() => BackupService.parse('[1,2]'), throwsA(isA<BackupException>()));
    expect(
      () => BackupService.parse(jsonEncode({'app': 'other'})),
      throwsA(isA<BackupException>()),
    );
  });

  test('rejects a backup from a newer format or schema', () {
    final map = jsonDecode(_encoded()) as Map<String, dynamic>;
    expect(
      () => BackupService.parse(jsonEncode({...map, 'formatVersion': 99})),
      throwsA(isA<BackupException>()),
    );
    expect(
      () => BackupService.parse(
        jsonEncode({...map, 'schemaVersion': DatabaseService.schemaVersion + 1}),
      ),
      throwsA(isA<BackupException>()),
    );
  });

  test('rejects incomplete or damaged backups', () {
    final map = jsonDecode(_encoded()) as Map<String, dynamic>;
    final missing = {...map, 'tables': {...map['tables'] as Map}..remove('blocks')};
    expect(() => BackupService.parse(jsonEncode(missing)), throwsA(isA<BackupException>()));

    final nested = {
      ...map,
      'tables': {
        ...map['tables'] as Map,
        'categories': [
          {'id': 'x', 'bad': [1, 2]},
        ],
      },
    };
    expect(() => BackupService.parse(jsonEncode(nested)), throwsA(isA<BackupException>()));
  });

  test('rejects a backup without categories', () {
    final tables = _tables()..['categories'] = [];
    final source = BackupService.encode(tables, now: DateTime(2026, 10, 7));
    expect(() => BackupService.parse(source), throwsA(isA<BackupException>()));
  });
}
