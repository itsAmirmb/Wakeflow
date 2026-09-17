import 'package:flutter/material.dart';
import '../services/stats_service.dart';
import '../services/day_key.dart';

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
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final today = dayKey(DateTime.now());
    final daily = await StatsService.instance.getDailyStats(today);
    final weekly = await StatsService.instance.getWeeklyStats();
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
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _DailyStatsView(stats: _daily!),
              _WeeklyStatsView(stats: _weekly!),
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
      return const Center(child: Text('No routine generated for today yet.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryRow(
          completedMinutes: stats.completedMinutes,
          plannedMinutes: stats.plannedMinutes,
          completedBlocks: stats.completedBlocks,
          skippedBlocks: stats.skippedBlocks,
        ),
        const SizedBox(height: 16),
        for (final stat in stats.categoryStats)
          if (stat.plannedMinutes > 0) _CategoryStatCard(stat: stat),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!hasAnyData)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('No routines generated in the last 7 days yet.'),
          )
        else ...[
          _WeekOverviewCard(stats: stats),
          const SizedBox(height: 16),
          for (final stat in stats.categoryStats)
            if (stat.plannedMinutes > 0) _CategoryStatCard(stat: stat),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final int completedMinutes;
  final int plannedMinutes;
  final int completedBlocks;
  final int skippedBlocks;

  const _SummaryRow({
    required this.completedMinutes,
    required this.plannedMinutes,
    required this.completedBlocks,
    required this.skippedBlocks,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatColumn(label: 'Completed', value: _formatMinutes(completedMinutes)),
            _StatColumn(label: 'Planned', value: _formatMinutes(plannedMinutes)),
            _StatColumn(label: 'Blocks done', value: '$completedBlocks'),
            _StatColumn(label: 'Skipped', value: '$skippedBlocks'),
          ],
        ),
      ),
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
                _StatColumn(
                  label: 'Completed',
                  value: _formatMinutes(stats.completedMinutes),
                ),
                _StatColumn(
                  label: 'Planned',
                  value: _formatMinutes(stats.plannedMinutes),
                ),
                _StatColumn(
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

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;

  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

class _CategoryStatCard extends StatelessWidget {
  final CategoryStat stat;

  const _CategoryStatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(stat.category.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stat.category.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${_formatMinutes(stat.completedMinutes)} / ${_formatMinutes(stat.plannedMinutes)}',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: stat.completionRatio.clamp(0, 1)),
            if (stat.skippedBlocks > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${stat.skippedBlocks} skipped',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
