import 'package:flutter/material.dart';

import '../models/day_mode.dart';
import '../models/category.dart';
import '../models/routine_target.dart';
import '../widgets/category_card.dart';
import '../services/routine_engine.dart';
import '../services/database_service.dart';
import '../services/day_key.dart';
import '../services/notification_service.dart';
import 'today_screen.dart';

class DayModeScreen extends StatefulWidget {
  final DayMode dayMode;
  final DateTime wakeTime;
  final RoutineTarget target;

  const DayModeScreen({
    super.key,
    required this.dayMode,
    required this.wakeTime,
    required this.target,
  });

  @override
  State<DayModeScreen> createState() => _DayModeScreenState();
}

class _DayModeScreenState extends State<DayModeScreen> {
  List<Category>? _categories;
  int _bufferMinutes = 10;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final categories = await DatabaseService.instance.getCategories();
    final settings = await DatabaseService.instance.getSettings();
    setState(() {
      _categories = categories;
      _bufferMinutes = settings.bufferMinutes;
    });
  }

  Future<void> _generateRoutine(BuildContext context) async {
    final categories = _categories;
    if (categories == null) return;

    final wakeTime = widget.wakeTime;

    // Usable time is bounded by whichever mode the user picked on the
    // Wake screen: a fixed clock time to finish by, or a fixed total
    // duration from wake time.
    final dayEnd = widget.target.endFrom(wakeTime);
    final today = dayKey(wakeTime);

    final placedBlocks = RoutineEngine.generateRoutine(
      categories: categories,
      startTime: wakeTime,
      dayEnd: dayEnd,
      bufferMinutes: _bufferMinutes,
    );

    // Metadata and blocks are written atomically so a crash can never
    // leave a half-registered day (resume relies on both agreeing).
    // Storage failures surface here — an unhandled error would only
    // log to the console and leave the button dead.
    try {
      await DatabaseService.instance.saveDayRoutine(
        day: today,
        dayMode: widget.dayMode,
        wakeTime: wakeTime,
        dayEnd: dayEnd,
        blocks: placedBlocks,
      );
    } catch (error) {
      debugPrint('Saving routine failed: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save the routine. Free up storage and try again.',
            ),
          ),
        );
      }
      return;
    }
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
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Woke up at ${widget.wakeTime.hour}:${widget.wakeTime.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 16,
                      ),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text(
                      'Generate Routine',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
