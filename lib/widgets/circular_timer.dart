import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/block.dart';
import 'block_status_style.dart';

/// Circular countdown for the current block.
///
/// Purely presentational: it derives everything from [elapsed], [planned]
/// and [status], so it stays correct after pause/resume or an app restart
/// (the source of truth remains Block.elapsedAt).
class CircularTimer extends StatelessWidget {
  final Duration elapsed;
  final Duration planned;
  final BlockStatus status;
  final double size;

  const CircularTimer({
    super.key,
    required this.elapsed,
    required this.planned,
    required this.status,
    this.size = 160,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final plannedSec = planned.inSeconds;
    final elapsedSec = elapsed.inSeconds;
    final isPending = status == BlockStatus.pending;
    final isPaused = status == BlockStatus.paused;
    final isOvertime = !isPending && elapsedSec > plannedSec;

    final progress = (isPending || plannedSec <= 0)
        ? 0.0
        : (elapsedSec / plannedSec).clamp(0.0, 1.0);

    final ringColor = isOvertime
        ? scheme.error
        : BlockStatusStyle.of(context, status).color;

    final displaySeconds = isPending
        ? plannedSec
        : isOvertime
            ? elapsedSec - plannedSec
            : plannedSec - elapsedSec;
    final timeText = '${isOvertime ? '+' : ''}${_format(displaySeconds)}';

    final caption = isPending
        ? 'Ready'
        : isOvertime
            ? 'Over time'
            : isPaused
                ? 'Paused'
                : 'of ${planned.inMinutes} min';

    return Semantics(
      label: '$timeText, $caption',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: TweenAnimationBuilder<double>(
            // Glide between the once-per-second updates instead of jumping.
            tween: Tween<double>(end: progress),
            duration: status == BlockStatus.active
                ? const Duration(seconds: 1)
                : const Duration(milliseconds: 250),
            curve: Curves.linear,
            builder: (context, value, _) => CustomPaint(
              painter: _RingPainter(
                progress: value,
                color: ringColor,
                trackColor: scheme.surfaceContainerHighest,
                strokeWidth: size * 0.07,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeText,
                      style: TextStyle(
                        fontSize: size * 0.2,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: isPaused
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      style: textTheme.labelMedium?.copyWith(
                        color: isOvertime ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// mm:ss, or h:mm:ss once the value reaches an hour.
  static String _format(int totalSeconds) {
    final s = math.max(0, totalSeconds);
    final h = s ~/ 3600;
    final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$sec' : '$m:$sec';
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = color;
    canvas.drawArc(arcRect, -math.pi / 2, 2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
