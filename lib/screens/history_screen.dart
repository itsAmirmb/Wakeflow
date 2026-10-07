import 'dart:async';

import 'package:flutter/material.dart';

import '../models/day_mode.dart';
import '../services/active_day.dart';
import '../services/database_service.dart';
import '../services/day_label.dart';
import '../services/history_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/stat_cards.dart';
import 'day_detail_screen.dart';

/// Past days, newest first, loaded a page at a time. Embedded in the Stats
/// tab; tapping a day opens its full detail.
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final List<HistoryDay> _days = [];
  String _today = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFirstPage());
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final today = await ActiveDay.resolve(
        DatabaseService.instance,
        DateTime.now(),
      );
      final page = await HistoryService.loadPage();
      if (!mounted) return;
      setState(() {
        _today = today;
        _days
          ..clear()
          ..addAll(page);
        _hasMore = page.length == HistoryService.pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await HistoryService.loadPage(offset: _days.length);
      if (!mounted) return;
      setState(() {
        _days.addAll(page);
        _hasMore = page.length == HistoryService.pageSize;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load more days.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load history.'),
            TextButton(onPressed: _loadFirstPage, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_days.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        message: 'No past routines yet. Finished days will appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _days.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _days.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: _loadMore,
                        child: const Text('Load older days'),
                      ),
              ),
            );
          }
          return _DayCard(day: _days[index], today: _today);
        },
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final HistoryDay day;
  final String today;

  const _DayCard({required this.day, required this.today});

  String get _counts {
    final parts = [
      if (day.doneBlocks > 0) '${day.doneBlocks} done',
      if (day.partialBlocks > 0) '${day.partialBlocks} partial',
      if (day.skippedBlocks > 0) '${day.skippedBlocks} skipped',
      if (day.unfinishedBlocks > 0)
        day.day == today
            ? '${day.unfinishedBlocks} to do'
            : '${day.unfinishedBlocks} not done',
    ];
    return parts.isEmpty ? 'No blocks' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = day.stats;
    final ratio = stats.plannedMinutes == 0
        ? 0.0
        : (stats.completedMinutes / stats.plannedMinutes).clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                DayDetailScreen(day: day.day, today: today),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatDayLabel(day.day, today: today),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (day.dayMode != null)
                    Text(
                      day.dayMode!.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${formatMinutes(stats.completedMinutes)} / '
                    '${formatMinutes(stats.plannedMinutes)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text('${(ratio * 100).round()}%'),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: ratio, minHeight: 8),
              ),
              const SizedBox(height: 8),
              Text(
                _counts,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
