import 'package:flutter/material.dart';
import '../services/stats_service.dart';
import '../services/active_day.dart';
import '../services/database_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/stat_cards.dart';
import 'history_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  DailyStats? _daily;
  WeeklyStats? _weekly;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // "Today" follows the day-reset time, like Home does.
    final today = await ActiveDay.resolve(
      DatabaseService.instance,
      DateTime.now(),
    );
    final parsed = DateTime.parse(today);
    final daily = await StatsService.instance.getDailyStats(today);
    // Noon avoids DST edge cases when stepping back whole days.
    final weekly = await StatsService.instance.getWeeklyStats(
      today: DateTime(parsed.year, parsed.month, parsed.day, 12),
    );
    if (!mounted) return;
    setState(() {
      _daily = daily;
      _weekly = weekly;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'This Week'),
            Tab(text: 'History'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _DailyStatsView(stats: _daily!),
              _WeeklyStatsView(stats: _weekly!),
              const HistoryView(),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyStatsView extends StatelessWidget {
  final DailyStats stats;

  const _DailyStatsView({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return const EmptyState(
        icon: Icons.wb_sunny_outlined,
        message: 'No routine generated for today yet.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SummaryRow(
          completedMinutes: stats.completedMinutes,
          plannedMinutes: stats.plannedMinutes,
          completedBlocks: stats.completedBlocks,
          skippedBlocks: stats.skippedBlocks,
        ),
        const SizedBox(height: 16),
        for (final stat in stats.categoryStats)
          if (stat.plannedMinutes > 0) CategoryStatCard(stat: stat),
      ],
    );
  }
}

class _WeeklyStatsView extends StatelessWidget {
  final WeeklyStats stats;

  const _WeeklyStatsView({required this.stats});

  @override
  Widget build(BuildContext context) {
    final hasAnyData = stats.plannedMinutes > 0;

    if (!hasAnyData) {
      return const EmptyState(
        icon: Icons.bar_chart_outlined,
        message: 'No routines generated in the last 7 days yet.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _WeekOverviewCard(stats: stats),
        const SizedBox(height: 16),
        for (final stat in stats.categoryStats)
          if (stat.plannedMinutes > 0) CategoryStatCard(stat: stat),
      ],
    );
  }
}

class _WeekOverviewCard extends StatelessWidget {
  final WeeklyStats stats;

  const _WeekOverviewCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                StatColumn(
                  label: 'Completed',
                  value: formatMinutes(stats.completedMinutes),
                ),
                StatColumn(
                  label: 'Planned',
                  value: formatMinutes(stats.plannedMinutes),
                ),
                StatColumn(
                  label: 'Completion',
                  value: '${(stats.completionRatio * 100).round()}%',
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: stats.completionRatio.clamp(0, 1)),
          ],
        ),
      ),
    );
  }
}
