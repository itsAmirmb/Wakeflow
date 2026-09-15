import 'dart:async';
import 'package:flutter/material.dart';
import '../models/day_mode.dart';
import '../models/block.dart';

class TodayScreen extends StatefulWidget {
  final DayMode dayMode;
  final List<Block> blocks;

  const TodayScreen({super.key, required this.dayMode, required this.blocks});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late List<Block> _blocks;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _blocks = widget.blocks;
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

  void _startTicking() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _stopTicking() {
    _timer?.cancel();
  }

  void _startCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    setState(() {
      _elapsed = Duration.zero;
      _blocks[index] = _blocks[index].copyWith(
        status: BlockStatus.active,
        actualStart: DateTime.now(),
      );
    });
    _startTicking();
  }

  void _pauseCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    _stopTicking();
    setState(() {
      _blocks[index] = _blocks[index].copyWith(status: BlockStatus.paused);
    });
  }

  void _resumeCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    setState(() {
      _blocks[index] = _blocks[index].copyWith(status: BlockStatus.active);
    });
    _startTicking();
  }

  void _completeCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    _stopTicking();
    setState(() {
      _blocks[index] = _blocks[index].copyWith(
        status: BlockStatus.completed,
        actualEnd: DateTime.now(),
      );
      _elapsed = Duration.zero;
    });
  }

  void _skipCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    _stopTicking();
    setState(() {
      _blocks[index] = _blocks[index].copyWith(
        status: BlockStatus.skipped,
        actualEnd: DateTime.now(),
      );
      _elapsed = Duration.zero;
    });
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
      appBar: AppBar(title: const Text('Today')),
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
                      _formatElapsed(_elapsed),
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