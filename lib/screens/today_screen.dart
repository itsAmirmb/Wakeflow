import 'dart:async';

import 'package:flutter/material.dart';

import '../models/day_mode.dart';
import '../models/app_settings.dart';
import '../models/checkpoint_report.dart';
import 'checkpoint_screen.dart';
import 'checkpoint_history_screen.dart';
import '../models/block.dart';
import '../models/category.dart';
import '../services/routine_engine.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../widgets/block_status_style.dart';
import '../widgets/circular_timer.dart';
import '../widgets/empty_state.dart';

class TodayScreen extends StatefulWidget {
  final DayMode dayMode;
  final List<Block> blocks;
  final String day; // yyyy-MM-dd this routine belongs to
  final List<Category> categories;

  /// Optional persistence boundary for embedding and widget tests.
  final Future<void> Function(Block block)? persistBlock;
  final Future<void> Function(Block block)? syncNotifications;
  final DatabaseService? database;
  final DateTime Function()? now;
  final Future<void> Function(AppSettings settings, DateTime wake, DateTime end)?
      syncCheckpointReminders;

  const TodayScreen({
    super.key,
    required this.dayMode,
    required this.blocks,
    required this.day,
    required this.categories,
    this.persistBlock,
    this.syncNotifications,
    this.database,
    this.now,
    this.syncCheckpointReminders,
  });

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  late List<Block> _blocks;
  Timer? _timer;
  AppSettings _settings = const AppSettings();
  bool _reviewing = false;
  bool _writeFailed = false;
  int? _reviewCount;
  String? _checkpointError;
  DatabaseService get _db => widget.database ?? DatabaseService.instance;
  DateTime get _now => (widget.now ?? DateTime.now)();

  Future<void> _refreshCheckpoints() async {
    try {
      final reviews = await _db.getCheckpoints(widget.day);
      if (!mounted) return;
      setState(() {
        _reviewCount = reviews.length;
        _checkpointError = null;
      });
      final settings = await _db.getSettings();
      final meta = await _db.getDayMeta(widget.day);
      if (!mounted || meta == null) return;
      final end = _deadline(meta.$3);
      if (widget.syncCheckpointReminders != null) {
        await widget.syncCheckpointReminders!(settings, meta.$2, end);
      } else {
        await NotificationService.instance.scheduleCheckpointReminders(
          day: widget.day, wakeTime: meta.$2, dayEnd: end,
          minutesOfDay: settings.checkpointMinutesOfDay,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checkpointError = 'Checkpoint data/reminders unavailable. Tap to retry.';
        });
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _db.getSettings();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      // Keep defaults; DONE then follows the default keep threshold.
    }
  }

  /// DONE only unlocks once the timer recorded at least the keep threshold,
  /// so a block can't be marked completed without real work behind it.
  bool _canComplete(Block block) => _settings.isProgressKept(
    elapsed: block.elapsedAt(DateTime.now()),
    plannedMinutes: block.plannedDurationMinutes,
  );

  String _unlockHint(Block block) {
    final t = _settings.keepThreshold(block.plannedDurationMinutes);
    final text = t.inSeconds % 60 == 0
        ? '${t.inMinutes} min'
        : '${t.inMinutes.toString().padLeft(2, '0')}:${(t.inSeconds % 60).toString().padLeft(2, '0')}';
    return 'DONE unlocks after $text on the timer';
  }

  DateTime _deadline(DateTime? saved) {
    if (saved != null) return saved;
    final ends = _blocks.map((b) => b.plannedEnd).whereType<DateTime>().toList()..sort();
    if (ends.isNotEmpty) return ends.last;
    final day = DateTime.parse(widget.day);
    return DateTime(day.year, day.month, day.day + 1);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshCheckpoints());
      unawaited(_loadSettings());
    }
  }

  @override
  void initState() {
    super.initState();
    _blocks = List<Block>.of(widget.blocks);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshCheckpoints());
    unawaited(_loadSettings());
    // If a block was already running when the app was closed, resume
    // ticking so the on-screen timer keeps advancing.
    final current = _currentBlock;
    if (current != null && current.status == BlockStatus.active) {
      _startTicking();
      unawaited(_syncNotifications(current));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _pendingWrite = Future<void>.value();

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _syncNotifications(Block block) async {
    try {
      if (widget.syncNotifications != null) {
        await widget.syncNotifications!(block);
      } else if (block.status == BlockStatus.active) {
        await NotificationService.instance.scheduleActiveBlockEnd(block);
      } else {
        await NotificationService.instance.cancelForBlock(block.id);
      }
    } catch (_) {
      _showError(
        'Could not update block reminders. Check notification permissions.',
      );
    }
  }

  // Keep writes and their notification updates in action order, even when the
  // user pauses/completes before the preceding database write finishes.
  Future<void> _persist(Block block) {
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        if (widget.persistBlock != null) {
          await widget.persistBlock!(block);
        } else {
          await _db.updateBlock(widget.day, block);
        }
      } catch (_) {
        _writeFailed = true;
        _showError(
          'Could not save block progress. Reopen the routine to reload saved state.',
        );
        return;
      }
      await _syncNotifications(block);
    });
    return _pendingWrite;
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

  // AnimatedSwitcher retains outgoing panels during the transition. Their
  // callbacks must never act on a newer state (even for the same block ID).
  void _actOn(Block expected, VoidCallback action) {
    if (!mounted || _reviewing || !identical(_currentBlock, expected)) return;
    action();
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
    if (!_canComplete(_blocks[index])) return;
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
    if (_reviewing) return;
    setState(() => _reviewing = true);
    try {
      await _pendingWrite;
      if (_writeFailed) {
        throw StateError('Reopen Today to reload saved block progress first.');
      }
      final settings = await _db.getSettings();
      final meta = await _db.getDayMeta(widget.day);
      if (!mounted) return;
      final dayEnd = _deadline(meta?.$3);
      final report = CheckpointReport.fromBlocks(blocks: _blocks,
        categories: widget.categories.where((c) => c.enabled).toList(),
        now: _now, dayEnd: dayEnd);
      final id = '${widget.day}-${DateTime.now().microsecondsSinceEpoch}';
      DateTime? previewedAt;
      final saved = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => CheckpointScreen(
          report: report,
          previewFuture: () {
            previewedAt = _now;
            return RoutineEngine.recalculateFromCheckpoint(
              currentBlocks: _blocks, categories: widget.categories,
              now: previewedAt!, dayEnd: dayEnd,
              bufferMinutes: settings.bufferMinutes);
          },
          save: (assessments, note, proposed) async {
            // Never silently apply a different plan than the one previewed.
            if (proposed != null && (previewedAt == null ||
                _now.difference(previewedAt!).inSeconds >= 60 ||
                (_now.isAfter(dayEnd) && previewedAt!.isBefore(dayEnd)))) {
              throw StateError('Preview expired. Go back and preview again.');
            }
            final oldFuture = _blocks.where((b) => b.status == BlockStatus.pending).toList();
            await _db.saveCheckpoint(id: id, day: widget.day, report: report,
              assessments: assessments, note: note, proposed: proposed);
            if (mounted) {
              setState(() {
                _reviewCount = (_reviewCount ?? 0) + 1;
                if (proposed != null) _blocks = proposed;
              });
            }
            if (proposed != null) {
              try {
                await NotificationService.instance.cancelForBlocks(oldFuture);
                await NotificationService.instance.scheduleForBlocks(proposed);
              } catch (_) {
                _showError('Review and plan saved, but reminders could not be updated.');
              }
            }
          },
        ),
      ));
      if (saved == true) await _refreshCheckpoints();
    } catch (error) {
      _showError('Could not open checkpoint. $error');
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
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
            tooltip: 'Review checkpoint',
            onPressed: _reviewing ? null : _runCheckpoint,
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(_reviewCount == null ? 'Saved reviews' : 'Saved reviews: $_reviewCount'),
            subtitle: Text(_checkpointError ?? 'Reminder times are not completed reviews'),
            onTap: () {
              if (_checkpointError != null) {
                unawaited(_refreshCheckpoints());
                return;
              }
              Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
                CheckpointHistoryScreen(day: widget.day, database: _db)));
            },
          ),
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
                    onStart: () => _actOn(currentBlock, _startCurrent),
                    onPause: () => _actOn(currentBlock, _pauseCurrent),
                    onResume: () => _actOn(currentBlock, _resumeCurrent),
                    onComplete: () => _actOn(currentBlock, _completeCurrent),
                    canComplete: _canComplete(currentBlock),
                    completeHint: _unlockHint(currentBlock),
                    onSkip: () => _actOn(currentBlock, _skipCurrent),
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
        subtitle: Text(_subtitle(style.label)),
      ),
    );
  }

  /// Finished blocks show the time the timer really recorded, not just the
  /// planned length.
  String _subtitle(String label) {
    final recorded = block.recordedSeconds;
    final finished =
        block.status == BlockStatus.completed ||
        block.status == BlockStatus.partial ||
        block.status == BlockStatus.skipped;
    if (!finished || recorded <= 0) {
      return '${block.plannedDurationMinutes}m · $label';
    }
    final active = recorded >= 60 ? '${recorded ~/ 60} min' : '$recorded s';
    return block.status == BlockStatus.partial
        ? '$active on timer · $label'
        : '${block.plannedDurationMinutes}m planned · $active on timer · $label';
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
  final bool canComplete;
  final String completeHint;

  const _CurrentBlockPanel({
    super.key,
    required this.block,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onComplete,
    required this.onSkip,
    required this.canComplete,
    required this.completeHint,
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
          const SizedBox(height: 12),
          CircularTimer(
            elapsed: showTimer
                ? block.elapsedAt(DateTime.now())
                : Duration.zero,
            planned: Duration(minutes: block.plannedDurationMinutes),
            status: block.status,
            size: MediaQuery.sizeOf(context).height < 640 ? 120 : 160,
          ),
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
                      onPressed: canComplete ? onComplete : null,
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
                      onPressed: canComplete ? onComplete : null,
                      icon: const Icon(Icons.check),
                      label: const Text('DONE'),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (showTimer && !canComplete) ...[
            const SizedBox(height: 8),
            Text(
              completeHint,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
