import 'package:flutter/material.dart';
import '../models/day_mode.dart';
import '../data/default_categories.dart';
import '../widgets/category_card.dart';
import '../services/routine_engine.dart';
import 'today_screen.dart';

class DayModeScreen extends StatelessWidget {
  final DayMode dayMode;
  final DateTime wakeTime;

  const DayModeScreen({
    super.key,
    required this.dayMode,
    required this.wakeTime,
  });

  void _generateRoutine(BuildContext context) {
    // Fixed day end: midnight, per spec example in §6.
    final dayEnd = DateTime(wakeTime.year, wakeTime.month, wakeTime.day + 1);
    final totalMinutes = dayEnd.difference(wakeTime).inMinutes;

    // No fixed events yet (Phase-later); flat 10-minute buffer per §15 example.
    const bufferMinutes = 10;

    final usableMinutes = RoutineEngine.calculateUsableMinutes(
      totalMinutes: totalMinutes,
      fixedEventMinutes: 0,
      bufferMinutes: bufferMinutes,
    );

    final allocation = RoutineEngine.allocateTime(
      categories: defaultCategories,
      usableMinutes: usableMinutes,
    );

    final blocks = RoutineEngine.splitIntoBlocks(
      categories: defaultCategories,
      allocation: allocation,
    );

    final placedBlocks = RoutineEngine.placeOnTimeline(
      blocks: blocks,
      startTime: wakeTime,
      bufferMinutes: bufferMinutes,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TodayScreen(dayMode: dayMode, blocks: placedBlocks),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WakeFlow')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Text(
                  '${dayMode.label} DAY',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Woke up at ${wakeTime.hour}:${wakeTime.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              children: defaultCategories
                  .map((category) => CategoryCard(category: category))
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: () => _generateRoutine(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('Generate Routine', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}