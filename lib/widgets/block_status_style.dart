import 'package:flutter/material.dart';
import '../models/block.dart';

/// Central mapping from [BlockStatus] to how it's shown in the UI.
/// Keeping this in one place means Today/Stats/anywhere else can't
/// drift into showing the same status with different colors or icons.
class BlockStatusStyle {
  final Color color;
  final IconData icon;
  final String label;

  const BlockStatusStyle({
    required this.color,
    required this.icon,
    required this.label,
  });

  static BlockStatusStyle of(BuildContext context, BlockStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case BlockStatus.pending:
        return BlockStatusStyle(
          color: scheme.onSurfaceVariant,
          icon: Icons.schedule,
          label: 'Pending',
        );
      case BlockStatus.active:
        return BlockStatusStyle(
          color: scheme.primary,
          icon: Icons.play_circle_fill,
          label: 'Active',
        );
      case BlockStatus.paused:
        return const BlockStatusStyle(
          color: Colors.amber,
          icon: Icons.pause_circle_filled,
          label: 'Paused',
        );
      case BlockStatus.completed:
        return const BlockStatusStyle(
          color: Colors.green,
          icon: Icons.check_circle,
          label: 'Completed',
        );
      case BlockStatus.skipped:
        return BlockStatusStyle(
          color: scheme.error,
          icon: Icons.skip_next,
          label: 'Skipped',
        );
      case BlockStatus.cancelled:
        return BlockStatusStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          icon: Icons.block,
          label: 'Cancelled',
        );
    }
  }
}
