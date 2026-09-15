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

  @override
  void initState() {
    super.initState();
    _blocks = widget.blocks;
  }

  int get _currentIndex => _blocks.indexWhere(
        (b) => b.status == BlockStatus.pending || b.status == BlockStatus.active,
      );

  void _startCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    setState(() {
      _blocks[index] = _blocks[index].copyWith(status: BlockStatus.active);
    });
  }

  void _completeCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    setState(() {
      _blocks[index] = _blocks[index].copyWith(status: BlockStatus.completed);
    });
  }

  void _skipCurrent() {
    final index = _currentIndex;
    if (index == -1) return;
    setState(() {
      _blocks[index] = _blocks[index].copyWith(status: BlockStatus.skipped);
    });
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
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