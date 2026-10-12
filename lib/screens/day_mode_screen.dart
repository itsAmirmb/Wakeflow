import 'package:flutter/material.dart';

import '../models/block.dart';
import '../models/day_mode.dart';
import '../models/category.dart';
import '../models/commitment.dart';
import '../models/routine_target.dart';
import '../widgets/category_editor.dart';
import '../widgets/category_timeline_bar.dart';
import '../widgets/commitment_editor.dart';
import '../widgets/weekly_schedule.dart';
import '../services/routine_engine.dart';
import '../services/database_service.dart';
import '../services/active_day.dart';
import '../services/day_key.dart';
import '../services/notification_service.dart';

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
  // Editable draft, in plan order. Every change is saved as it is made, so
  // the next day starts from the last settings used.
  List<Category>? _categories;
  Future<void> _pendingSave = Future<void>.value();
  int _bufferMinutes = 10;
  int _longBreakMinutes = 30;
  // Fixed events of the day being planned; blocks are scheduled around them.
  // Every commitment, for the weekly table (the planner re-reads the day's
  // own commitments when generating).
  List<Commitment> _allCommitments = const [];
  String? _planDay;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final categories = await DatabaseService.instance.getCategories();
    final settings = await DatabaseService.instance.getSettings();
    var planDay = dayKey(widget.wakeTime);
    var allCommitments = <Commitment>[];
    try {
      planDay = await ActiveDay.resolve(DatabaseService.instance, widget.wakeTime);
      allCommitments = await DatabaseService.instance.getCommitments();
    } catch (_) {
      // Planning still works without them.
    }
    if (!mounted) return;
    setState(() {
      _categories = List<Category>.of(categories);
      _bufferMinutes = settings.bufferMinutes;
      _longBreakMinutes = settings.longBreakMinutes;
      _planDay = planDay;
      _allCommitments = allCommitments;
    });
  }

  Future<void> _addCommitment() async {
    final day = _planDay;
    if (day == null) return;
    final result = await showCommitmentEditor(
      context,
      presetDate: DateTime.parse(day),
    );
    final saved = result?.saved;
    if (saved == null || !mounted) return;
    try {
      await DatabaseService.instance.saveCommitment(saved);
      final all = await DatabaseService.instance.getCommitments();
      if (mounted) setState(() => _allCommitments = all);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the commitment.')),
        );
      }
    }
  }

  /// Saves the draft (with its order as priority). Writes are chained so they
  /// land in edit order; a failure is retried when the routine is generated.
  void _saveDraft() {
    final draft = _categories;
    if (draft == null) return;
    final ordered = [
      for (var i = 0; i < draft.length; i++) draft[i].copyWith(priority: i + 1),
    ];
    _pendingSave = _pendingSave.then((_) async {
      try {
        await DatabaseService.instance.saveCategories(ordered);
      } catch (_) {}
    });
  }

  void _updateCategory(int index, Category category) {
    setState(() => _categories![index] = category);
    _saveDraft();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _categories!.removeAt(oldIndex);
      _categories!.insert(newIndex, moved);
    });
    _saveDraft();
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
    await _pendingSave;
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
    // The day follows the user's reset time, not midnight.
    String today;
    try {
      today = await ActiveDay.resolve(DatabaseService.instance, wakeTime);
    } catch (_) {
      today = dayKey(wakeTime);
    }

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

    // Fixed events of the whole routine, which may run past midnight
    // (re-read: one may have just been added).
    var busy = <BusyInterval>[];
    try {
      busy = [
        for (final slot in Commitment.slotsBetween(
          await DatabaseService.instance.getCommitments(),
          DateTime.parse(today),
          dayEnd,
        ))
          slot.interval,
      ];
    } catch (_) {}

    final placedBlocks = kept.isEmpty
        ? RoutineEngine.generateRoutine(
            categories: categories,
            startTime: wakeTime,
            dayEnd: dayEnd,
            bufferMinutes: _bufferMinutes,
            longBreakMinutes: _longBreakMinutes,
            busy: busy,
          )
        : RoutineEngine.recalculateFromCheckpoint(
            currentBlocks: kept,
            categories: categories,
            now: wakeTime,
            dayEnd: dayEnd,
            bufferMinutes: _bufferMinutes,
            longBreakMinutes: _longBreakMinutes,
            busy: busy,
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
    // Hand control back to Home (through the Wake screen), which opens
    // Today. Back from Today then lands on Home, not on this planning step.
    Navigator.pop(context, true);
  }

  /// Weekly table of fixed commitments (display only) plus the reorder hint.
  Widget _buildScheduleHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final planDate = DateTime.tryParse(_planDay ?? '') ?? widget.wakeTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Schedule',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Add a commitment for today',
                icon: const Icon(Icons.add),
                onPressed: _addCommitment,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: WeeklyScheduleView(
            commitments: _allCommitments,
            weekOf: planDate,
            highlightWeekday: planDate.weekday,
            compact: true,
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Divider(height: 1),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Time split',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CategoryTimelineBar(
            key: const ValueKey('daymode-timeline'),
            categories: _categories ?? const [],
            onChanged: (updated) {
              setState(() => _categories = List<Category>.of(updated));
              _saveDraft();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Drag the lines to change each share · drag the cards below to '
            'reorder (the order is the order of your blocks).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
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
                        'Started at ${widget.wakeTime.hour}:${widget.wakeTime.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    // The weekly table scrolls with the categories, so the
                    // list keeps its room on small screens.
                    header: _buildScheduleHeader(context),
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
