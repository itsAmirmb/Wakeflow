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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checking = true;
  int _tabIndex = 0;

  // If a routine was already generated for today, this holds what's
  // needed to jump straight back into it from the Home tab.
  DayMode? _todayDayMode;
  List<Block>? _todayBlocks;
  List<Category>? _todayCategories;

  @override
  void initState() {
    super.initState();
    _checkForTodayRoutine();
  }

  Future<void> _checkForTodayRoutine() async {
    final today = dayKey(DateTime.now());
    final meta = await DatabaseService.instance.getDayMeta(today);

    if (meta == null) {
      // No routine generated yet today — show the normal Start Day flow.
      setState(() => _checking = false);
      return;
    }

    final (dayMode, _) = meta;
    final blocks = await DatabaseService.instance.getBlocksForDay(today);
    final categories = await DatabaseService.instance.getCategories();

    if (!mounted) return;

    // Meta exists but blocks got cleared somehow — fall back safely to
    // the normal Start Day flow instead of showing a broken "continue".
    setState(() {
      _checking = false;
      if (blocks.isNotEmpty) {
        _todayDayMode = dayMode;
        _todayBlocks = blocks;
        _todayCategories = categories;
      }
    });
  }

  void _openTodayScreen(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TodayScreen(
          dayMode: _todayDayMode!,
          blocks: _todayBlocks!,
          day: dayKey(DateTime.now()),
          categories: _todayCategories!,
        ),
      ),
    );
    // Block statuses may have changed (started/completed/skipped) while
    // on the Today screen, or a checkpoint may have replaced the whole
    // future — refresh so the Home summary reflects that on return.
    if (mounted) _checkForTodayRoutine();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasTodayRoutine = _todayBlocks != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasTodayRoutine ? Icons.check_circle_outline : Icons.wb_sunny_outlined,
              size: 56,
              color: scheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              hasTodayRoutine ? "Today's routine is ready" : 'Good morning 👋',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasTodayRoutine
                  ? _todaySummary()
                  : 'Ready to plan your day?',
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (hasTodayRoutine)
              Semantics(
                button: true,
                label: "Continue today's routine",
                child: ElevatedButton.icon(
                  onPressed: () => _openTodayScreen(context),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Continue Routine', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(240, 56),
                  ),
                ),
              )
            else
              Semantics(
                button: true,
                label: 'Start Day',
                child: ElevatedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const WakeScreen()),
                    );
                    if (mounted) _checkForTodayRoutine();
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(200, 56),
                  ),
                  child: const Text('Start Day', style: TextStyle(fontSize: 18)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _todaySummary() {
    final blocks = _todayBlocks!;
    final done = blocks.where((b) => b.status == BlockStatus.completed).length;
    return '$done/${blocks.length} blocks done · ${_todayDayMode!.label}';
  }
}