import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/database_service.dart';

/// Read-only snapshots: later category/plan edits never rewrite reflections.
class CheckpointHistoryScreen extends StatefulWidget {
  final String day;
  final DatabaseService? database;
  const CheckpointHistoryScreen({super.key, required this.day, this.database});

  @override
  State<CheckpointHistoryScreen> createState() => _CheckpointHistoryScreenState();
}

class _CheckpointHistoryScreenState extends State<CheckpointHistoryScreen> {
  late String _day = widget.day;
  late Future<List<Map<String, Object?>>> _reviews =
      (widget.database ?? DatabaseService.instance).getCheckpoints(_day);

  Future<void> _chooseDay() async {
    final date = await showDatePicker(context: context,
      initialDate: DateTime.parse(_day), firstDate: DateTime(2000),
      lastDate: DateTime(2100));
    if (date == null || !mounted) return;
    setState(() {
      _day = date.toIso8601String().substring(0, 10);
      _reviews = (widget.database ?? DatabaseService.instance).getCheckpoints(_day);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Reviews · $_day'), actions: [
      IconButton(onPressed: _chooseDay, tooltip: 'Choose review date',
        icon: const Icon(Icons.calendar_month)),
    ]),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _reviews,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load reviews. Reopen to retry.'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final reviews = snapshot.data!;
        if (reviews.isEmpty) return const Center(child: Text('No saved reviews yet'));
        return ListView(children: [for (final row in reviews) _review(row)]);
      },
    ),
  );

  Widget _review(Map<String, Object?> row) {
    final report = jsonDecode(row['report'] as String) as Map<String, dynamic>;
    final assessments = jsonDecode(row['assessments'] as String) as Map<String, dynamic>;
    final time = DateTime.parse(row['reviewedAt'] as String);
    final clock = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final distill = report['distill'] as Map<String, dynamic>?;
    final realByCategory =
        (distill?['realSeconds'] as Map<String, dynamic>?) ?? const {};
    const labels = {'reached': 'Reached', 'partial': 'Partly reached', 'notReached': 'Not reached'};
    return ExpansionTile(
      title: Text('Review at $clock'),
      subtitle: Text(
        distill != null
            ? 'Distilled'
            : row['recalculated'] == 1
            ? 'Future recalculated'
            : 'Plan unchanged',
      ),
      children: [
        if (distill != null)
          ListTile(
            title: Text(
              'Distilled: kept ${distill['completedBlocks']} done + '
              '${distill['partialBlocks']} partial · discarded '
              '${distill['discardedBlocks']} block(s) '
              '(${distill['discardedPlannedMinutes']} min planned)',
            ),
          ),
        for (final progress in report['categories'] as List)
          ListTile(
            title: Text('${progress['name']} · ${labels[assessments[progress['id']]] ?? 'Not assessed'}'),
            subtitle: Text('Target: ${(progress['targetSeconds'] as int) ~/ 60}m · '
              'Expected by review: ${(progress['expectedSeconds'] as int) ~/ 60}m · '
              'Recorded: ${(progress['actualSeconds'] as int) ~/ 60}m'
              '${distill == null ? '' : ' · Real work: ${((realByCategory[progress['id']] as int?) ?? 0) ~/ 60}m'}'),
          ),
        if ((row['note'] as String).isNotEmpty) ListTile(title: Text(row['note'] as String)),
      ],
    );
  }
}
