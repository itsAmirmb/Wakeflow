import 'package:flutter/material.dart';
import '../models/day_mode.dart';
import '../models/block.dart';

class TodayScreen extends StatelessWidget {
  final DayMode dayMode;
  final List<Block> blocks;

  const TodayScreen({super.key, required this.dayMode, required this.blocks});

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              dayMode.label,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: blocks.length,
              itemBuilder: (context, index) {
                final block = blocks[index];
                return ListTile(
                  leading: Text(
                    _formatTime(block.plannedStart),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  title: Text(block.title),
                  subtitle: Text('${block.plannedDurationMinutes}m'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}