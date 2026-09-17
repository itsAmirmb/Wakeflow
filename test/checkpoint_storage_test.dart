import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/models/checkpoint_report.dart';
import 'package:wakeflow/services/database_service.dart';

void main() {
  sqfliteFfiInit();

  test('saving reflection preserves blocks and never invents timer minutes', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 7, onCreate: DatabaseService.createSchema));
    addTearDown(db.close);
    final service = DatabaseService.forTesting(db);
    const day = '2026-09-17';
    final blocks = [Block(id: 'work', categoryId: 'c', title: 'Work',
      plannedDurationMinutes: 60, plannedStart: DateTime(2026, 9, 17, 10),
      status: BlockStatus.paused, accumulatedSeconds: 59)];
    await service.saveBlocksForDay(day, blocks);
    final before = await db.query('blocks');
    final report = CheckpointReport.fromBlocks(blocks: blocks, categories: [],
      now: DateTime(2026, 9, 17, 11), dayEnd: DateTime(2026, 9, 17, 20));
    expect(await service.getCheckpoints(day), isEmpty);
    await service.saveCheckpoint(id: 'review-1', day: day, report: report,
      assessments: {'c': CheckpointAssessment.reached}, note: 'Finished the task');
    expect(await db.query('blocks'), before);
    final saved = await service.getCheckpoints(day);
    expect(saved, hasLength(1));
    expect(saved.single['recalculated'], 0);
    expect(jsonDecode(saved.single['assessments'] as String), {'c': 'reached'});
    final snapshot = jsonDecode(saved.single['report'] as String);
    expect(snapshot['categories'][0]['actualSeconds'], 59);
    expect(saved.single['note'], 'Finished the task');
  });
}
