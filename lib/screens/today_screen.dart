import 'dart:async';
import 'package:flutter/material.dart';
import '../models/day_mode.dart';
import '../models/block.dart';
import '../models/category.dart';
import '../services/routine_engine.dart';
import '../services/database_service.dart';

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

  /// Writes a single block's current state to the DB. Called after
  /// every status change so progress survives closing the app.
  Future<void> _persist(Block block) {
    return DatabaseService.instance.updateBlock(widget.day, block);
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
    final dayEnd = DateTime(now.year, now.month, now.day + 1);

    final recalculated = RoutineEngine.recalculateFromCheckpoint(
      currentBlocks: _blocks,
      categories: widget.categories,
      now: now,
      dayEnd: dayEnd,
      bufferMinutes: 10,
    );

    setState(() {
      _blocks = recalculated;
    });

    // Checkpoint rewrites the whole future portion, so it's simplest
    // to replace the day's rows wholesale rather than diff them.
    await DatabaseService.instance.saveBlocksForDay(widget.day, recalculated);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Checkpoint: future routine recalculated')),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
            padding: const EdgeInsets.all(16.0),
            child: Text(
              widget.dayMode.label,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _blocks.length,
              itemBuilder: (context, index) {
                final block = _blocks[index];
                final isCurrent = index == currentIndex;
                return ListTile(
                  tileColor: isCurrent ? Colors.deepPurple.withOpacity(0.08) : null,
                  leading: Text(
                    _formatTime(block.plannedStart),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  title: Text(block.title),
                  subtitle: Text('${block.plannedDurationMinutes}m · ${block.status.name}'),
                );
              },
            ),
          ),
          if (currentBlock != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text('Current: ${currentBlock.title}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (currentBlock.status == BlockStatus.active ||
                      currentBlock.status == BlockStatus.paused) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatElapsed(currentBlock.elapsedAt(DateTime.now())),
                      style: const TextStyle(fontSize: 28, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (currentBlock.status == BlockStatus.pending)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _startCurrent,
                            child: const Text('START'),
                          ),
                        ),
                      if (currentBlock.status == BlockStatus.active) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _pauseCurrent,
                            child: const Text('PAUSE'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _completeCurrent,
                            child: const Text('COMPLETE'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _skipCurrent,
                            child: const Text('SKIP'),
                          ),
                        ),
                      ],
                      if (currentBlock.status == BlockStatus.paused) ...[
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _resumeCurrent,
                            child: const Text('RESUME'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _completeCurrent,
                            child: const Text('COMPLETE'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Day complete 🎉'),
            ),
        ],
      ),
    );
  }
}