import 'package:flutter/material.dart';

import 'wake_screen.dart';
import 'today_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import '../models/day_mode.dart';
import '../models/block.dart';
import '../models/category.dart';
import '../services/database_service.dart';
import '../services/day_key.dart';
import '../services/notification_service.dart';
import '../services/routine_engine.dart';

typedef HomeRoutine = ({
  String day,
  DayMode dayMode,
  List<Block> blocks,
  List<Category> categories,
});

class HomeScreen extends StatefulWidget {
  final DateTime Function()? now;
  final Future<HomeRoutine?> Function(String day)? loadRoutine;

  const HomeScreen({super.key, this.now, this.loadRoutine});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checking = true;
  int _tabIndex = 0;

  // If a routine was already generated for today, this holds what's
  // needed to jump straight back into it from the Home tab.
  HomeRoutine? _routine;
  bool _opening = false;
  bool _distilling = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  Future<HomeRoutine?> _loadRoutine(String day) async {
    if (widget.loadRoutine != null) return widget.loadRoutine!(day);
    final db = DatabaseService.instance;
    final meta = await db.getDayMeta(day);
    if (meta == null) return null;
    final blocks = await db.getBlocksForDay(day);
    if (blocks.isEmpty) return null;
    return (
      day: day,
      dayMode: meta.$1,
      blocks: blocks,
      categories: await db.getCategories(),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkForTodayRoutine();
  }

  Future<void> _checkForTodayRoutine() async {
    try {
      final day = dayKey(_now);
      final routine = await _loadRoutine(day);
      if (!mounted) return;
      setState(() {
        _routine = day == dayKey(_now) && routine?.blocks.isNotEmpty == true
            ? routine
            : null;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _routine = null;
        _checking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load today’s routine. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openTodayScreen(BuildContext context) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      // Re-read before navigating: the date or settings may have changed
      // while Home was open. Never relabel cached blocks with another day.
      await _checkForTodayRoutine();
      if (!context.mounted) return;
      final routine = _routine;
      if (routine == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TodayScreen(
            dayMode: routine.dayMode,
            blocks: routine.blocks,
            day: routine.day,
            categories: routine.categories,
          ),
        ),
      );
      if (mounted) await _checkForTodayRoutine();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Distillation: keep the real work done today (completed blocks and
  /// unfinished ones above the user's threshold) and drop everything else.
  /// Discarded blocks are removed, so stats only reflect work that actually
  /// happened. Planning the rest of the day is left to Start Day.
  Future<void> _distill() async {
    if (_opening || _distilling) return;
    setState(() => _distilling = true);
    try {
      final db = DatabaseService.instance;
      final day = dayKey(_now);
      final meta = await db.getDayMeta(day);
      final blocks = await db.getBlocksForDay(day);
      if (meta == null || blocks.isEmpty) {
        await _checkForTodayRoutine();
        return;
      }
      final settings = await db.getSettings();
      final now = _now;
      final ends = blocks.map((b) => b.plannedEnd).whereType<DateTime>().toList()
        ..sort();
      final date = DateTime.parse(day);
      final dayEnd =
          meta.$3 ??
          (ends.isNotEmpty ? ends.last : DateTime(date.year, date.month, date.day + 1));

      final result = RoutineEngine.distill(
        currentBlocks: blocks,
        now: now,
        settings: settings,
      );
      if (!mounted) return;
      if (result.discarded.isEmpty) {
        _snack('Nothing to distill — every block already holds real progress.');
        return;
      }

      final keptMinutes = result.partialSeconds ~/ 60;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Distill today?'),
          content: Text(
            'Keeps: ${result.completed.length} completed block(s)'
            '${result.partial.isEmpty ? '' : ' and ${result.partial.length} partial session(s) ($keptMinutes min)'}.\n'
            'Discards: ${result.discarded.length} unfinished block(s) '
            '(${result.discardedPlannedMinutes} min planned).\n'
            'Nothing new is planned. Use Start Day afterwards to plan the '
            'rest of your day.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Distill'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      // Meta and blocks are replaced atomically; the resolved deadline is
      // persisted so the day keeps its deadline once pending blocks are gone.
      await db.saveDayRoutine(
        day: day,
        dayMode: meta.$1,
        wakeTime: meta.$2,
        dayEnd: dayEnd,
        blocks: result.blocks,
      );
      try {
        await NotificationService.instance.cancelForBlocks(
          blocks
              .where(
                (b) =>
                    b.status != BlockStatus.completed &&
                    b.status != BlockStatus.partial,
              )
              .toList(),
        );
      } catch (_) {
        _snack('Distilled, but block reminders could not be updated.');
      }
      await _checkForTodayRoutine();
      _snack(
        'Distilled: kept ${result.completed.length + result.partial.length}, '
        'discarded ${result.discarded.length}.',
      );
    } catch (_) {
      _snack('Could not distill today’s routine. Please try again.');
    } finally {
      if (mounted) setState(() => _distilling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final Widget body;
    final String title;
    switch (_tabIndex) {
      case 1:
        body = const StatsScreen();
        title = 'Stats';
        break;
      case 2:
        body = const SettingsScreen();
        title = 'Settings';
        break;
      default:
        body = _buildHomeTab(context);
        title = 'WakeFlow';
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(key: ValueKey(_tabIndex), child: body),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasTodayRoutine = _routine != null;
    // Nothing left to run (e.g. after Distill): offer Start Day to plan more.
    final hasActionable =
        hasTodayRoutine &&
        _routine!.blocks.any(
          (b) =>
              b.status == BlockStatus.pending ||
              b.status == BlockStatus.active ||
              b.status == BlockStatus.paused,
        );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasActionable
                  ? Icons.check_circle_outline
                  : Icons.wb_sunny_outlined,
              size: 56,
              color: scheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              hasActionable
                  ? "Today's routine is ready"
                  : hasTodayRoutine
                  ? 'Plan the rest of your day'
                  : 'Good morning 👋',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasTodayRoutine ? _todaySummary() : 'Ready to plan your day?',
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (hasActionable) ...[
              Semantics(
                button: true,
                label: "Continue today's routine",
                child: ElevatedButton.icon(
                  onPressed: _opening || _distilling
                      ? null
                      : () => _openTodayScreen(context),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(
                    'Continue Routine',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(240, 56),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: "Distill today's routine",
                child: OutlinedButton.icon(
                  onPressed: _opening || _distilling ? null : _distill,
                  icon: _distilling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.science_outlined),
                  label: const Text('Distill', style: TextStyle(fontSize: 18)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(240, 56),
                  ),
                ),
              ),
            ] else
              Semantics(
                button: true,
                label: 'Start Day',
                child: ElevatedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WakeScreen(),
                      ),
                    );
                    if (mounted) _checkForTodayRoutine();
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(200, 56),
                  ),
                  child: const Text(
                    'Start Day',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
              if (hasTodayRoutine) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _opening ? null : () => _openTodayScreen(context),
                  child: const Text("View today's log"),
                ),
              ],
          ],
        ),
      ),
    );
  }

  String _todaySummary() {
    final blocks = _routine!.blocks;
    final done = blocks.where((b) => b.status == BlockStatus.completed).length;
    final hasActionable = blocks.any(
      (b) =>
          b.status == BlockStatus.pending ||
          b.status == BlockStatus.active ||
          b.status == BlockStatus.paused,
    );
    if (hasActionable) {
      return '$done/${blocks.length} blocks done · ${_routine!.dayMode.label}';
    }
    final realSeconds = blocks
        .where(
          (b) =>
              b.status == BlockStatus.completed ||
              b.status == BlockStatus.partial,
        )
        .fold<int>(0, (sum, b) => sum + b.recordedSeconds);
    return '${realSeconds ~/ 60} min of real work kept · ${_routine!.dayMode.label}';
  }
}
