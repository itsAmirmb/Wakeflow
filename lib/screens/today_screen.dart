import 'dart:async';

import 'package:flutter/material.dart';

import '../models/day_mode.dart';
import '../models/block.dart';
import '../models/category.dart';
import '../services/routine_engine.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../widgets/block_status_style.dart';
import '../widgets/empty_state.dart';

class TodayScreen extends StatefulWidget {
  final DayMode dayMode;
  final List<Block> blocks;
  final String day; // yyyy-MM-dd this routine belongs to
  final List<Category> categories;

  const TodayScreen({
    super.key,
    required this.dayMode,
    required this.blocks,
    required this.day,
    required this.categories,
  });

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late List<Block> _blocks;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _blocks = widget.blocks;
    // If a block was already running when the app was closed, resume
    // ticking so the on-screen timer keeps advancing.
    final current = _currentBlock;
    if (current != null && current.status == BlockStatus.active) {
      _startTicking();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _currentIndex => _blocks.indexWhere(
    (b) =>
        b.status == BlockStatus.pending ||
        b.status == BlockStatus.active ||
        b.status == BlockStatus.paused,
  );

  Block? get _currentBlock {
    final index = _currentIndex;
    return index == -1 ? null : _blocks[index];
  }

  /// Writes a single block's current state to the DB, and cancels its
  /// scheduled notifications now that it's no longer pending (so a
  /// stale Start/End notification doesn't fire after the user already
  /// acted on the block manually).
  Future<void> _persist(Block block) async {
    await DatabaseService.instance.updateBlock(widget.day, block);
    await NotificationService.instance.cancelForBlock(block.id);
  }

  void _startTicking() {
    _timer?.cancel();
    // The timer only drives a repaint every second — the actual
    // elapsed value always comes from Block.elapsedAt(now), which is
    // derived from accumulatedSeconds + runningSince, not from this
    // counter. So even if ticking is interrupted (app backgrounded),
    // the displayed time is correct the moment it resumes.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
    });
  }

  void _stopTicking() {
    _timer?.cancel();
  }

  void _startCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    final updated = _blocks[index].copyWith(
      status: BlockStatus.active,
      actualStart: DateTime.now(),
      accumulatedSeconds: 0,
      runningSince: DateTime.now(),
    );
    setState(() {
      _blocks[index] = updated;
    });
    _startTicking();
    _persist(updated);
  }

  void _pauseCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    _stopTicking();
    final block = _blocks[index];
    // Freeze the running stretch into accumulatedSeconds, then clear
    // runningSince so elapsedAt() stops adding live time while paused.
    final updated = block.copyWith(
      status: BlockStatus.paused,
      accumulatedSeconds: block.elapsedAt(DateTime.now()).inSeconds,
      runningSince: null,
    );
    setState(() {
      _blocks[index] = updated;
    });
    _persist(updated);
  }

  void _resumeCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    final updated = _blocks[index].copyWith(
      status: BlockStatus.active,
      runningSince: DateTime.now(),
    );
    setState(() {
      _blocks[index] = updated;
    });
    _startTicking();
    _persist(updated);
  }

  void _completeCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    _stopTicking();
    final block = _blocks[index];
    final updated = block.copyWith(
      status: BlockStatus.completed,
      actualEnd: DateTime.now(),
      accumulatedSeconds: block.elapsedAt(DateTime.now()).inSeconds,
      runningSince: null,
    );
    setState(() {
      _blocks[index] = updated;
    });
    _persist(updated);
  }

  void _skipCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    _stopTicking();
    final block = _blocks[index];
    final updated = block.copyWith(
      status: BlockStatus.skipped,
      actualEnd: DateTime.now(),
      accumulatedSeconds: block.elapsedAt(DateTime.now()).inSeconds,
      runningSince: null,
    );
    setState(() {
      _blocks[index] = updated;
    });
    _persist(updated);
  }

  Future<void> _runCheckpoint() async {
    final now = DateTime.now();
    final settings = await DatabaseService.instance.getSettings();
    final meta = await DatabaseService.instance.getDayMeta(widget.day);

    // Prefer the deadline the user actually picked on the Wake screen;
    // only fall back to midnight for routines created before the
    // deadline was persisted (or if the meta row is missing).
    final dayEnd = meta?.$3 ?? DateTime(now.year, now.month, now.day + 1);

    // Cancel notifications for the old future blocks before they get
    // replaced — otherwise stale Start/End alerts could fire for
    // times that no longer match the recalculated routine.
    final oldFuture = _blocks
        .where((b) => b.status == BlockStatus.pending)
        .toList();
    await NotificationService.instance.cancelForBlocks(oldFuture);

    final recalculated = RoutineEngine.recalculateFromCheckpoint(
      currentBlocks: _blocks,
      categories: widget.categories,
      now: now,
      dayEnd: dayEnd,
      bufferMinutes: settings.bufferMinutes,
    );

    setState(() {
      _blocks = recalculated;
    });

    // Checkpoint rewrites the whole future portion, so it's simplest
    // to replace the day's rows wholesale rather than diff them.
    await DatabaseService.instance.saveBlocksForDay(widget.day, recalculated);
    await NotificationService.instance.scheduleForBlocks(recalculated);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Checkpoint: future routine recalculated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex;
    final currentBlock = currentIndex == -1 ? null : _blocks[currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Checkpoint / Recalculate',
            onPressed: _runCheckpoint,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  widget.dayMode.label,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '· ${_blocks.where((b) => b.status == BlockStatus.completed).length}/${_blocks.length} done',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _blocks.isEmpty
                ? const EmptyState(
                    icon: Icons.event_note_outlined,
                    message: 'No blocks in this routine',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _blocks.length,
                    itemBuilder: (context, index) {
                      final block = _blocks[index];
                      final isCurrent = index == currentIndex;
                      return _BlockTile(block: block, isCurrent: isCurrent);
                    },
                  ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(sizeFactor: animation, child: child),
            ),
            child: currentBlock != null
                ? _CurrentBlockPanel(
                    key: ValueKey('${currentBlock.id}-${currentBlock.status}'),
                    block: currentBlock,
                    onStart: _startCurrent,
                    onPause: _pauseCurrent,
                    onResume: _resumeCurrent,
                    onComplete: _completeCurrent,
                    onSkip: _skipCurrent,
                  )
                : const _DayCompletePanel(key: ValueKey('day-complete')),
          ),
        ],
      ),
    );
  }
}

class _BlockTile extends StatelessWidget {
  final Block block;
  final bool isCurrent;

  const _BlockTile({required this.block, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = BlockStatusStyle.of(context, block.status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrent
            ? scheme.primaryContainer.withValues(alpha: 0.5)
            : null,
        borderRadius: BorderRadius.circular(14),
        border: isCurrent
            ? Border.all(color: scheme.primary, width: 1.5)
            : null,
      ),
      child: ListTile(
        leading: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatTime(block.plannedStart),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Icon(style.icon, color: style.color, size: 18),
          ],
        ),
        title: Text(
          block.title,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
            decoration: block.status == BlockStatus.skipped
                ? TextDecoration.lineThrough
                : null,
          ),
        ),
        subtitle: Text('${block.plannedDurationMinutes}m · ${style.label}'),
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _DayCompletePanel extends StatelessWidget {
  const _DayCompletePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🎉', style: TextStyle(fontSize: 32)),
          SizedBox(height: 8),
          Text(
            'Day complete',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _CurrentBlockPanel extends StatelessWidget {
  final Block block;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  const _CurrentBlockPanel({
    super.key,
    required this.block,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onComplete,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showTimer =
        block.status == BlockStatus.active ||
        block.status == BlockStatus.paused;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'CURRENT',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            block.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          if (showTimer) ...[
            const SizedBox(height: 8),
            Text(
              _formatElapsed(block.elapsedAt(DateTime.now())),
              style: const TextStyle(
                fontSize: 32,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (block.status == BlockStatus.pending)
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Start ${block.title}',
                    child: ElevatedButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('START'),
                    ),
                  ),
                ),
              if (block.status == BlockStatus.active) ...[
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Pause ${block.title}',
                    child: OutlinedButton.icon(
                      onPressed: onPause,
                      icon: const Icon(Icons.pause),
                      label: const Text('PAUSE'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Mark ${block.title} as complete',
                    child: ElevatedButton.icon(
                      onPressed: onComplete,
                      icon: const Icon(Icons.check),
                      label: const Text('DONE'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Skip ${block.title}',
                    child: OutlinedButton.icon(
                      onPressed: onSkip,
                      icon: const Icon(Icons.skip_next),
                      label: const Text('SKIP'),
                    ),
                  ),
                ),
              ],
              if (block.status == BlockStatus.paused) ...[
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Resume ${block.title}',
                    child: ElevatedButton.icon(
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('RESUME'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Mark ${block.title} as complete',
                    child: ElevatedButton.icon(
                      onPressed: onComplete,
                      icon: const Icon(Icons.check),
                      label: const Text('DONE'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
