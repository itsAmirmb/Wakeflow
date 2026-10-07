import 'package:flutter/material.dart';

import '../services/stats_service.dart';

class SummaryRow extends StatelessWidget {
  final int completedMinutes;
  final int plannedMinutes;
  final int completedBlocks;
  final int skippedBlocks;

  const SummaryRow({
    required this.completedMinutes,
    required this.plannedMinutes,
    required this.completedBlocks,
    required this.skippedBlocks,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            StatColumn(label: 'Completed', value: formatMinutes(completedMinutes)),
            StatColumn(label: 'Planned', value: formatMinutes(plannedMinutes)),
            StatColumn(label: 'Blocks done', value: '$completedBlocks'),
            StatColumn(label: 'Skipped', value: '$skippedBlocks'),
          ],
        ),
      ),
    );
  }
}

class StatColumn extends StatelessWidget {
  final String label;
  final String value;

  const StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class CategoryStatCard extends StatelessWidget {
  final CategoryStat stat;

  const CategoryStatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(stat.category.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stat.category.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${formatMinutes(stat.completedMinutes)} / ${formatMinutes(stat.plannedMinutes)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: stat.completionRatio.clamp(0, 1),
                minHeight: 8,
              ),
            ),
            if (stat.skippedBlocks > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${stat.skippedBlocks} skipped',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
