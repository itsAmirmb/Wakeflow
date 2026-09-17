import 'package:flutter/material.dart';
import '../models/day_mode.dart';
import '../models/category.dart';
import '../widgets/category_card.dart';
import '../services/routine_engine.dart';
import '../services/database_service.dart';
import '../services/day_key.dart';
import '../services/notification_service.dart';
import 'today_screen.dart';

class DayModeScreen extends StatefulWidget {
  final DayMode dayMode;
  final DateTime wakeTime;

  const DayModeScreen({
    super.key,
    required this.dayMode,
    required this.wakeTime,
  });

  @override
  State<DayModeScreen> createState() => _DayModeScreenState();
}

class _DayModeScreenState extends State<DayModeScreen> {
  List<Category>? _categories;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await DatabaseService.instance.getCategories();
    setState(() => _categories = categories);
  }

  Future<void> _generateRoutine(BuildContext context) async {
    final categories = _categories;
    if (categories == null) return;

    final wakeTime = widget.wakeTime;

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
      categories: categories,
      usableMinutes: usableMinutes,
    );

    final blocks = RoutineEngine.splitIntoBlocks(
      categories: categories,
      allocation: allocation,
    );

    final placedBlocks = RoutineEngine.placeOnTimeline(
      blocks: blocks,
      startTime: wakeTime,
      bufferMinutes: bufferMinutes,
    );

    final today = dayKey(wakeTime);
    await DatabaseService.instance.saveDayMeta(
      day: today,
      dayMode: widget.dayMode,
      wakeTime: wakeTime,
    );
    await DatabaseService.instance.saveBlocksForDay(today, placedBlocks);
    await NotificationService.instance.scheduleForBlocks(placedBlocks);

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TodayScreen(
          dayMode: widget.dayMode,
          blocks: placedBlocks,
          day: today,
          categories: categories,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    return Scaffold(
      appBar: AppBar(title: const Text('WakeFlow')),
      body: categories == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Text(
                        '${widget.dayMode.label} DAY',
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Woke up at ${widget.wakeTime.hour}:${widget.wakeTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: categories
                        .map((category) => CategoryCard(category: category))
                        .toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: () => _generateRoutine(context),
                    style: ElevatedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child:
                        const Text('Generate Routine', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
    );
  }
}