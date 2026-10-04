import 'package:flutter/material.dart';

import '../models/block.dart';
import '../models/day_mode.dart';
import '../models/category.dart';
import '../models/routine_target.dart';
import '../widgets/category_editor.dart';
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
  // Editable draft, in plan order. Changes are saved when the routine is
  // generated (not while editing), so backing out discards them.
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
    if (!mounted) return;
    setState(() {
      _categories = List<Category>.of(categories);
      _bufferMinutes = settings.bufferMinutes;
    });
  }

  void _updateCategory(int index, Category category) {
    setState(() => _categories![index] = category);
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _categories!.removeAt(oldIndex);
      _categories!.insert(newIndex, moved);
    });
  }

  Future<void> _generateRoutine(BuildContext context) async {
    final draft = _categories;
    if (draft == null) return;
    // Order is stored as priority, so the Settings tab and later days show
    // the same order the routine is built in.
    final categories = [
      for (var i = 0; i < draft.length; i++) draft[i].copyWith(priority: i + 1),
    ];
    if (!categories.any((c) => c.enabled)) return;
    try {
      await DatabaseService.instance.saveCategories(categories);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save category changes. Please try again.'),
          ),
        );
      }
      return;
    }

    final wakeTime = widget.wakeTime;

    // Usable time is bounded by whichever mode the user picked on the
    // Wake screen: a fixed clock time to finish by, or a fixed total
    // duration from wake time.
    final dayEnd = widget.target.endFrom(wakeTime);
    final today = dayKey(wakeTime);

    // Planning again on the same day (e.g. after Distill) must never wipe
    // work that already happened: completed and partial blocks are kept and
    // credited, and only the remaining time is planned.
    var kept = <Block>[];
    DateTime? originalWake;
    try {
      final db = DatabaseService.instance;
      kept = (await db.getBlocksForDay(today))
          .where(
            (b) =>
                b.status == BlockStatus.completed ||
                b.status == BlockStatus.partial,
          )
          .toList();
      originalWake = (await db.getDayMeta(today))?.$2;
    } catch (_) {
      kept = [];
    }

    final placedBlocks = kept.isEmpty
        ? RoutineEngine.generateRoutine(
            categories: categories,
            startTime: wakeTime,
            dayEnd: dayEnd,
            bufferMinutes: _bufferMinutes,
          )
        : RoutineEngine.recalculateFromCheckpoint(
            currentBlocks: kept,
            categories: categories,
            now: wakeTime,
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
        wakeTime: originalWake ?? wakeTime,
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
    try {
      await NotificationService.instance.scheduleForBlocks(placedBlocks);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Routine saved, but block reminders could not be updated.'),
        ));
      }
    }
    // Today refreshes fixed checkpoint reminders from the persisted metadata.

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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Drag to reorder · the order is the order of your blocks. '
                    'Changes are saved as your category settings.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    itemCount: categories.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return Card(
                        key: ValueKey(category.id),
                        child: Opacity(
                          opacity: category.enabled ? 1 : 0.55,
                          child: Row(
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.fromLTRB(12, 8, 4, 8),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                              Expanded(
                                child: CategoryEditorTile(
                                  category: category,
                                  onChanged: (updated) =>
                                      _updateCategory(index, updated),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!categories.any((c) => c.enabled))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Enable at least one category to generate a routine.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: categories.any((c) => c.enabled)
                        ? () => _generateRoutine(context)
                        : null,
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
