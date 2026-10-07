import 'dart:async';

import 'package:flutter/material.dart';

import '../models/day_mode.dart';
import '../models/app_settings.dart';
import '../models/checkpoint_report.dart';
import '../models/progress_report.dart';
import 'progress_report_screen.dart';
import 'checkpoint_screen.dart';
import 'checkpoint_history_screen.dart';
import '../models/block.dart';
import '../models/category.dart';
import '../models/commitment.dart';
import '../services/break_state.dart';
import '../services/checkpoint_gate.dart';
import '../services/routine_engine.dart';
import '../services/database_service.dart';
import '../services/alarm_sound.dart';
import 'category_notes_screen.dart';
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
  final Future<void> Function(DateTime when, String nextTitle)? scheduleBreakAlarm;
  final Future<void> Function()? cancelBreakAlarm;

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
    this.scheduleBreakAlarm,
    this.cancelBreakAlarm,
  });

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  late List<Block> _blocks;
  Timer? _timer;
  AppSettings _settings = const AppSettings();
  List<Commitment> _commitments = const [];
  bool _reviewing = false;
  bool _alarmSilenced = false;
  bool _breakRang = false;
  Map<String, int> _noteCounts = const {};
  Timer? _gateTimer;
  DateTime? _gateWake;
  DateTime? _gateEnd;
  DateTime? _lastReviewAt;
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
        _lastReviewAt = reviews.isEmpty
            ? null
            : DateTime.tryParse('${reviews.first['reviewedAt']}');
      });
      final settings = await _db.getSettings();
      final meta = await _db.getDayMeta(widget.day);
      if (!mounted || meta == null) return;
      final end = _deadline(meta.$3);
      _gateWake = meta.$2;
      _gateEnd = end;
      setState(() => _settings = settings);
      // Evaluated before reminders are synced, so a notification failure can
      // never let a due checkpoint slip through.
      _evaluateGate();
      if (widget.syncCheckpointReminders != null) {
        await widget.syncCheckpointReminders!(settings, meta.$2, end);
      } else {
        await NotificationService.instance.scheduleCheckpointReminders(
          day: widget.day, wakeTime: meta.$2, dayEnd: end,
          // Nothing left to review once every block is finished or distilled.
          minutesOfDay:
              _hasUnfinished ? settings.checkpointMinutesOfDay : const [],
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

  /// Fixed events of this routine day: shown in the timeline, respected when
  /// a checkpoint re-plans, and reminded shortly before they start.
  Future<void> _loadCommitments() async {
    try {
      final commitments = await _db.getCommitmentsForDay(widget.day);
      if (!mounted) return;
      setState(() => _commitments = commitments);
      if (widget.syncNotifications != null) return; // injected: no plugin
      final date = DateTime.parse(widget.day);
      await NotificationService.instance.scheduleCommitmentReminders(
        day: widget.day,
        items: [
          for (final c in commitments)
            (title: c.title, start: c.intervalOn(date).start),
        ],
      );
    } catch (_) {
      // Optional extra: the plan itself does not depend on it.
    }
  }

  List<BusyInterval> _busy() {
    final date = DateTime.parse(widget.day);
    return [for (final c in _commitments) c.intervalOn(date)];
  }

  /// Blocks and fixed events in time order (blocks keep their own order).
  List<Widget> _timelineItems(int currentIndex) {
    final date = DateTime.parse(widget.day);
    final waiting = [..._commitments]
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    Widget tile(Commitment c) =>
        _CommitmentTile(key: ValueKey('commitment-${c.id}'), commitment: c);
    final items = <Widget>[];
    for (var i = 0; i < _blocks.length; i++) {
      final start = _blocks[i].plannedStart;
      if (start != null) {
        while (waiting.isNotEmpty &&
            !waiting.first.intervalOn(date).start.isAfter(start)) {
          items.add(tile(waiting.removeAt(0)));
        }
      }
      final block = _blocks[i];
      items.add(
        _BlockTile(
          block: block,
          isCurrent: i == currentIndex,
          noteCount: _noteCounts[block.categoryId] ?? 0,
          onNotes: () => _openNotes(block),
        ),
      );
    }
    items.addAll(waiting.map(tile));
    return items;
  }

  /// Notes are optional: the screen works the same when none exist.
  Future<void> _loadNoteCounts() async {
    try {
      final counts = await _db.getNoteCounts();
      if (mounted) setState(() => _noteCounts = counts);
    } catch (_) {}
  }

  Future<void> _openNotes(Block block) async {
    Category? category;
    for (final c in widget.categories) {
      if (c.id == block.categoryId) category = c;
    }
    if (category == null) return;
    await showCategoryNotesSheet(context, category);
    unawaited(_loadNoteCounts());
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _db.getSettings();
      if (mounted) setState(() => _settings = settings);
      _resumeBreakTicking();
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

  bool get _hasUnfinished => _blocks.any(
    (b) =>
        b.status == BlockStatus.pending ||
        b.status == BlockStatus.active ||
        b.status == BlockStatus.paused,
  );

  /// The checkpoint time that is owed a review right now, if any.
  DateTime? _dueCheckpoint() {
    final wake = _gateWake;
    final end = _gateEnd;
    if (wake == null || end == null || !_hasUnfinished) return null;
    return CheckpointGate.dueAt(
      minutesOfDay: _settings.checkpointMinutesOfDay,
      wake: wake,
      dayEnd: end,
      now: _now,
      lastReviewAt: _lastReviewAt,
    );
  }

  /// A due checkpoint opens the review at once and cannot be skipped.
  void _evaluateGate() {
    if (!mounted || _reviewing) return;
    if (_dueCheckpoint() != null) unawaited(_runCheckpoint(forced: true));
  }

  BreakState? _break() => BreakState.derive(
    blocks: _blocks,
    bufferMinutes: _settings.bufferMinutes,
    longBreakMinutes: _settings.longBreakMinutes,
    now: _now,
  );

  void _resumeBreakTicking() {
    final state = _break();
    if (state != null && !state.isOver(_now)) {
      // Re-arm after an app restart/resume: the alarm is only ever scheduled
      // when COMPLETE is tapped, so it would otherwise be lost.
      unawaited(_scheduleBreakAlarm(state));
      if (_timer?.isActive != true) _startTicking();
    }
  }

  Future<void> _scheduleBreakAlarm(BreakState state) async {
    try {
      if (widget.scheduleBreakAlarm != null) {
        await widget.scheduleBreakAlarm!(state.end, state.next.title);
      } else if (widget.syncNotifications == null) {
        await NotificationService.instance.scheduleBreakEnd(
          when: state.end,
          nextTitle: state.next.title,
          soundUri: _settings.breakAlarmUri,
        );
      }
    } catch (_) {
      _showError('Could not schedule the break alarm. Check notification permissions.');
    }
  }

  Future<void> _cancelBreakAlarm() async {
    unawaited(AlarmSound.stop());
    try {
      if (widget.cancelBreakAlarm != null) {
        await widget.cancelBreakAlarm!();
      } else if (widget.syncNotifications == null) {
        await NotificationService.instance.cancelBreakAlarm();
      }
    } catch (_) {
      // Nothing useful to tell the user: the alarm times out by itself.
    }
  }

  /// Checkpoint reminders are pointless once nothing is left to run; without
  /// this they would still fire later in the day.
  void _cancelCheckpointReminders() {
    if (widget.syncNotifications != null ||
        widget.syncCheckpointReminders != null) {
      return;
    }
    unawaited(
      NotificationService.instance
          .cancelCheckpointReminders(day: widget.day)
          .catchError((_) {}),
    );
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
      unawaited(_loadCommitments());
    }
  }

  @override
  void initState() {
    super.initState();
    _blocks = List<Block>.of(widget.blocks);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshCheckpoints());
    unawaited(_loadSettings());
    unawaited(_loadCommitments());
    unawaited(_loadNoteCounts());
    _gateTimer = Timer.periodic(const Duration(seconds: 15), (_) => _evaluateGate());
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
    _gateTimer?.cancel();
    unawaited(AlarmSound.stop());
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
      if (!mounted) return;
      setState(() {});
      // Keep ticking while a block runs or a break is counting down.
      final running = _currentBlock?.status == BlockStatus.active;
      final breakState = _break();
      // Break just ended while the app is open: ring in-app (alarm stream),
      // independent of notification channel/ringer settings.
      if (breakState != null && breakState.isOver(_now) &&
          !_alarmSilenced && !_breakRang) {
        _breakRang = true;
        // The in-app alarm replaces the scheduled notification, so the two
        // never ring on top of each other.
        unawaited(_cancelBreakAlarm());
        unawaited(
          AlarmSound.play(
            'confirm_screen',
            loop: true,
            uri: _settings.breakAlarmUri,
          ),
        );
      }
      final onBreak = breakState?.isOver(_now) == false;
      if (!running && !onBreak) _stopTicking();
    });
  }

  void _stopTicking() {
    _timer?.cancel();
  }

  // AnimatedSwitcher retains outgoing panels during the transition. Their
  // callbacks must never act on a newer state (even for the same block ID).
  void _actOn(Block expected, VoidCallback action) {
    if (!mounted || _reviewing || !identical(_currentBlock, expected)) return;
    if (_dueCheckpoint() != null) {
      _evaluateGate();
      return;
    }
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
    unawaited(_cancelBreakAlarm()); // also stops a still-ringing break alarm
    // First task of the day has its own sound; later ones share another.
    final firstOfDay = !_blocks.any(
      (b) => b.id != updated.id && b.actualStart != null,
    );
    unawaited(
      AlarmSound.play(firstOfDay ? 'session_start' : 'task_start'),
    );
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
      _alarmSilenced = false;
      _breakRang = false;
    });
    _persist(updated);
    // The break timer starts now; its end rings like an alarm.
    final state = _break();
    if (state != null) {
      _startTicking();
      unawaited(_scheduleBreakAlarm(state));
      // Break starts: short or long break sound (the end alarm is separate).
      unawaited(AlarmSound.play(state.isLong ? 'long_break' : 'short_break'));
    } else if (!_hasUnfinished) {
      unawaited(AlarmSound.play('session_complete'));
      _cancelCheckpointReminders();
    }
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
    if (!_hasUnfinished) _cancelCheckpointReminders();
  }

  Future<void> _runCheckpoint({bool forced = false}) async {
    if (_reviewing) return;
    setState(() => _reviewing = true);
    // A forced checkpoint stops the timer (below) and rings until the user
    // acts on the review screen.
    if (forced) unawaited(AlarmSound.play('teq_teq'));
    try {
      // A forced review freezes a running block first, so what is previewed
      // is exactly what gets saved.
      if (forced && _currentBlock?.status == BlockStatus.active) {
        _pauseCurrent();
      }
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
      ProgressReport? progress;
      final saved = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => CheckpointScreen(
          report: report,
          forceDistill: forced,
          hasUnfinished: _hasUnfinished,
          previewFuture: () {
            previewedAt = _now;
            return RoutineEngine.recalculateFromCheckpoint(
              currentBlocks: _blocks, categories: widget.categories,
              now: previewedAt!, dayEnd: dayEnd,
              bufferMinutes: settings.bufferMinutes,
              longBreakMinutes: settings.longBreakMinutes,
              busy: _busy());
          },
          distillPreview: () {
            unawaited(AlarmSound.stop());
            previewedAt = _now;
            return RoutineEngine.distill(
              currentBlocks: _blocks,
              now: previewedAt!,
              settings: settings,
            );
          },
          saveDistill: (assessments, note, result) async {
            // Same freshness rule as a new plan: never apply a different
            // distillation than the one previewed.
            // Only a running timer makes a preview go stale; a paused or
            // pending block distills to the same result at any time.
            final running = _blocks.any((b) => b.status == BlockStatus.active);
            if (previewedAt == null ||
                (running && _now.difference(previewedAt!).inSeconds >= 60)) {
              throw StateError('Preview expired. Go back and preview again.');
            }
            final before = List<Block>.of(_blocks);
            final built = ProgressReport.build(
              before: before,
              result: result,
              categories: widget.categories.where((c) => c.enabled).toList(),
              now: _now,
              dayEnd: dayEnd,
              assessments: assessments,
              note: note,
            );
            // Checkpoint row, block replacement and the pinned deadline are
            // one transaction, so a failure leaves the day untouched.
            await _db.saveCheckpoint(
              id: id,
              day: widget.day,
              report: report,
              assessments: assessments,
              note: note,
              proposed: result.blocks,
              distill: built.toJson(),
              persistDayEnd: dayEnd,
            );
            progress = built;
            unawaited(_cancelBreakAlarm());
            if (mounted) {
              _stopTicking();
              setState(() {
                _reviewCount = (_reviewCount ?? 0) + 1;
                _blocks = List<Block>.of(result.blocks);
              });
              if (!_hasUnfinished) _cancelCheckpointReminders();
            }
            try {
              await NotificationService.instance.cancelForBlocks(
                before
                    .where(
                      (b) =>
                          b.status != BlockStatus.completed &&
                          b.status != BlockStatus.partial,
                    )
                    .toList(),
              );
            } catch (_) {
              _showError(
                'Distilled and saved, but block reminders could not be updated.',
              );
            }
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
      if (saved == true) {
        await _refreshCheckpoints();
        final distilled = progress;
        if (distilled != null && mounted) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => ProgressReportScreen(report: distilled),
            ),
          );
        }
      }
    } catch (error) {
      _showError('Could not open checkpoint. $error');
    } finally {
      unawaited(AlarmSound.stop());
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex;
    final currentBlock = currentIndex == -1 ? null : _blocks[currentIndex];
    final breakState = _break();

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
                : ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: _timelineItems(currentIndex),
                  ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(sizeFactor: animation, child: child),
            ),
            child: breakState != null
                ? _BreakPanel(
                    key: ValueKey(
                      'break-${breakState.next.id}-${breakState.isOver(_now)}',
                    ),
                    state: breakState,
                    now: _now,
                    alarmSilenced: _alarmSilenced,
                    onStartNext: () => _actOn(breakState.next, _startCurrent),
                    onStopAlarm: () {
                      setState(() => _alarmSilenced = true);
                      unawaited(_cancelBreakAlarm());
                    },
                  )
                : currentBlock != null
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
                    noteCount: _noteCounts[currentBlock.categoryId] ?? 0,
                    onNotes: () => _openNotes(currentBlock),
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
  final int noteCount;
  final VoidCallback? onNotes;

  const _BlockTile({
    required this.block,
    required this.isCurrent,
    this.noteCount = 0,
    this.onNotes,
  });

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
        // Only categories that have notes show the shortcut.
        trailing: noteCount > 0 && onNotes != null
            ? IconButton(
                tooltip: 'Notes',
                onPressed: onNotes,
                icon: Badge(
                  label: Text('$noteCount'),
                  child: const Icon(Icons.sticky_note_2_outlined),
                ),
              )
            : null,
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
  final int noteCount;
  final VoidCallback? onNotes;

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
    this.noteCount = 0,
    this.onNotes,
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
          SizedBox(
            height: 32,
            child: Stack(
              alignment: Alignment.center,
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
                if (noteCount > 0 && onNotes != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Notes',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 32,
                      ),
                      onPressed: onNotes,
                      icon: Badge(
                        label: Text('$noteCount'),
                        child: const Icon(Icons.sticky_note_2_outlined),
                      ),
                    ),
                  ),
              ],
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
                  child: _ActionButton(
                    semanticsLabel: 'Start ${block.title}',
                    label: 'START',
                    icon: Icons.play_arrow,
                    filled: true,
                    onPressed: onStart,
                  ),
                ),
              if (block.status == BlockStatus.active) ...[
                Expanded(
                  child: _ActionButton(
                    semanticsLabel: 'Pause ${block.title}',
                    label: 'PAUSE',
                    icon: Icons.pause,
                    onPressed: onPause,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    semanticsLabel: 'Mark ${block.title} as complete',
                    label: 'DONE',
                    icon: Icons.check,
                    filled: true,
                    onPressed: canComplete ? onComplete : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    semanticsLabel: 'Skip ${block.title}',
                    label: 'SKIP',
                    icon: Icons.skip_next,
                    onPressed: onSkip,
                  ),
                ),
              ],
              if (block.status == BlockStatus.paused) ...[
                Expanded(
                  child: _ActionButton(
                    semanticsLabel: 'Resume ${block.title}',
                    label: 'RESUME',
                    icon: Icons.play_arrow,
                    filled: true,
                    onPressed: onResume,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    semanticsLabel: 'Mark ${block.title} as complete',
                    label: 'DONE',
                    icon: Icons.check,
                    filled: true,
                    onPressed: canComplete ? onComplete : null,
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

/// Rest between two blocks: a countdown ring, then a "break over" state while
/// the end-of-break alarm may still be ringing.
class _BreakPanel extends StatelessWidget {
  final BreakState state;
  final DateTime now;
  final bool alarmSilenced;
  final VoidCallback onStartNext;
  final VoidCallback onStopAlarm;

  const _BreakPanel({
    super.key,
    required this.state,
    required this.now,
    required this.alarmSilenced,
    required this.onStartNext,
    required this.onStopAlarm,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = state.isOver(now);
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
            over
                ? (state.isLong ? 'LONG BREAK OVER' : 'BREAK OVER')
                : (state.isLong ? 'LONG BREAK' : 'BREAK'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: over ? scheme.error : scheme.tertiary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Next: ${state.next.title}',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          CircularTimer(
            elapsed: state.elapsed(now),
            planned: state.total,
            status: BlockStatus.active,
            size: MediaQuery.sizeOf(context).height < 640 ? 120 : 160,
            color: over ? scheme.error : scheme.tertiary,
            caption: over ? 'Break over' : 'Break',
            showOvertime: false,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Start ${state.next.title}',
                  child: FilledButton.icon(
                    onPressed: onStartNext,
                    icon: const Icon(Icons.play_arrow),
                    label: _OneLine(over ? 'START NEXT' : 'START NOW'),
                  ),
                ),
              ),
              if (over && !alarmSilenced) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onStopAlarm,
                    icon: const Icon(Icons.alarm_off),
                    label: const _OneLine('STOP ALARM'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A fixed event (class, work) shown in the timeline. Not a block: it has no
/// timer and never counts toward "done".
class _CommitmentTile extends StatelessWidget {
  final Commitment commitment;

  const _CommitmentTile({super.key, required this.commitment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.event),
        title: Text(commitment.title),
        subtitle: Text(
          'Fixed · ${Commitment.hm(commitment.startMinutes)}–${Commitment.hm(commitment.endMinutes)}',
        ),
      ),
    );
  }
}

/// Button label that always stays on one line: it shrinks to fit instead of
/// wrapping, so a row of buttons never grows taller on narrow screens.
class _OneLine extends StatelessWidget {
  final String text;

  const _OneLine(this.text);

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}

/// One action of the timer panel: icon + single-line label, equal width via
/// the surrounding Expanded, with tight horizontal padding.
class _ActionButton extends StatelessWidget {
  final String semanticsLabel;
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.semanticsLabel,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
    );
    final iconWidget = Icon(icon, size: 18);
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: filled
          ? ElevatedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: iconWidget,
              label: _OneLine(label),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: iconWidget,
              label: _OneLine(label),
            ),
    );
  }
}
