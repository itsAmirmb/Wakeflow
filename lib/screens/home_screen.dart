import 'package:flutter/material.dart';
import 'wake_screen.dart';
import 'today_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
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

    if (blocks.isEmpty) {
      // Meta exists but blocks got cleared somehow — fall back safely.
      setState(() => _checking = false);
      return;
    }

    // A routine already exists for today — resume it directly instead
    // of asking the user to go through Wake Check again.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => TodayScreen(
          dayMode: dayMode,
          blocks: blocks,
          day: today,
          categories: categories,
        ),
      ),
    );
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wb_sunny_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'Good morning 👋',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Ready to plan your day?',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            Semantics(
              button: true,
              label: 'Start Day',
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const WakeScreen()),
                  );
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
}