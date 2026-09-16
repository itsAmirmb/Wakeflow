import 'package:flutter/material.dart';
import 'wake_screen.dart';
import 'today_screen.dart';
import '../services/database_service.dart';
import '../services/day_key.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checking = true;

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

    return Scaffold(
      appBar: AppBar(title: const Text('WakeFlow')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Good morning 👋',
              style: TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const WakeScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Start Day', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}