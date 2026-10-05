import 'package:flutter/material.dart';

import '../models/checkpoint_report.dart';
import '../models/progress_report.dart';

/// Shown right after a checkpoint distillation: what was really done today.
class ProgressReportScreen extends StatelessWidget {
  final ProgressReport report;

  const ProgressReportScreen({super.key, required this.report});

  static String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }

  static const _labels = {
    CheckpointAssessment.reached: 'Reached',
    CheckpointAssessment.partial: 'Partly reached',
    CheckpointAssessment.notReached: 'Not reached',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expected = report.expectedSeconds;
    final onTrack = expected > 0
        ? (report.realSeconds / expected).clamp(0.0, 1.0)
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Progress report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _duration(report.realSeconds),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('of real work recorded today'),
                  if (onTrack != null) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: onTrack),
                    const SizedBox(height: 6),
                    Text(
                      '${(onTrack * 100).round()}% of the '
                      '${_duration(expected)} scheduled by now',
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(label: Text('${report.completedBlocks} done')),
                      Chip(label: Text('${report.partialBlocks} partial')),
                      Chip(
                        label: Text(
                          '${report.discardedBlocks} discarded · '
                          '${report.discardedPlannedMinutes} min planned',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${report.remainingMinutes} min left · finish by '
                    '${TimeOfDay.fromDateTime(report.dayEnd).format(context)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final c in report.categories)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.category.icon} ${c.category.name}'.trim(),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: c.targetSeconds > 0
                          ? (c.realSeconds / c.targetSeconds).clamp(0.0, 1.0)
                          : 0,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Real work: ${c.realMinutes} min · '
                      'Scheduled by now: ${c.expectedMinutes} min · '
                      'Planned: ${c.targetMinutes} min',
                    ),
                    Text('${c.completedBlocks} done · ${c.partialBlocks} partial'),
                    if (c.assessment != null)
                      Text('Your assessment: ${_labels[c.assessment]}'),
                  ],
                ),
              ),
            ),
          if (report.note.trim().isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.notes),
                title: Text(report.note.trim()),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Home re-reads the day when it is reached again and offers
              // Start Day, because nothing is left to run after a distill.
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                icon: const Icon(Icons.wb_sunny_outlined),
                label: const Text('Plan the rest of the day'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to Today'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
