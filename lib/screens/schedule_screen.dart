import 'package:flutter/material.dart';

import '../models/commitment.dart';
import '../services/database_service.dart';
import '../widgets/weekly_schedule.dart';

/// Read-only weekly timetable of the user's fixed commitments.
/// Commitments themselves are edited in Settings.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<Commitment>? _commitments;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final commitments = await DatabaseService.instance.getCommitments();
      if (!mounted) return;
      setState(() {
        _commitments = commitments;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final commitments = _commitments;
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly schedule')),
      body: _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load the schedule.'),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : commitments == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  WeeklyScheduleView(
                    commitments: commitments,
                    weekOf: now,
                    highlightWeekday: now.weekday,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tap a block for details. Outlined blocks are one-off '
                    'events. Edit commitments in Settings.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
