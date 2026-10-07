import 'package:flutter/material.dart';

import '../models/block.dart';
import '../models/category.dart';
import '../models/commitment.dart';
import '../models/day_mode.dart';
import '../services/database_service.dart';
import '../services/day_label.dart';
import '../services/stats_service.dart';
import '../widgets/block_status_style.dart';
import '../widgets/stat_cards.dart';
import 'checkpoint_history_screen.dart';

/// Read-only record of one past day: totals, per-category progress, every
/// block with what actually happened, and a way into its checkpoint reviews.
class DayDetailScreen extends StatefulWidget {
  final String day;

  /// The app's current day (yyyy-MM-dd), for the "Today"/"Yesterday" title.
  final String today;

  const DayDetailScreen({super.key, required this.day, required this.today});

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

typedef _DayData = ({
  List<Block> blocks,
  DailyStats stats,
  List<Category> categories,
  (DayMode, DateTime, DateTime?)? meta,
  int reviews,
});

class _DayDetailScreenState extends State<DayDetailScreen> {
  late Future<_DayData> _future = _load();

  Future<_DayData> _load() async {
    final db = DatabaseService.instance;
    final blocks = await db.getBlocksForDay(widget.day);
    final categories = await db.getCategories();
    final meta = await db.getDayMeta(widget.day);
    final reviews = (await db.getCheckpoints(widget.day)).length;
    return (
      blocks: blocks,
      stats: StatsService.instance.buildDailyStats(
        widget.day,
        blocks,
        categories,
      ),
      categories: categories,
      meta: meta,
      reviews: reviews,
    );
  }

  static String _clock(DateTime? t) => t == null
      ? '--:--'
      : Commitment.hm(t.hour * 60 + t.minute);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(formatDayLabel(widget.day, today: widget.today)),
      ),
      body: FutureBuilder<_DayData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load this day.'),
                  TextButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _content(context, data);
        },
      ),
    );
  }

  Widget _content(BuildContext context, _DayData data) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final meta = data.meta;
    final isPast = widget.day != widget.today;
    final categoriesById = {for (final c in data.categories) c.id: c};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (meta != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${meta.$1.label} day · started ${_clock(meta.$2)}',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        SummaryRow(
          completedMinutes: data.stats.completedMinutes,
          plannedMinutes: data.stats.plannedMinutes,
          completedBlocks: data.stats.completedBlocks,
          skippedBlocks: data.stats.skippedBlocks,
        ),
        const SizedBox(height: 8),
        for (final stat in data.stats.categoryStats)
          if (stat.plannedMinutes > 0) CategoryStatCard(stat: stat),
        if (data.reviews > 0) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text(
                data.reviews == 1
                    ? '1 checkpoint review'
                    : '${data.reviews} checkpoint reviews',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CheckpointHistoryScreen(day: widget.day),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Blocks', style: text.titleMedium),
        const SizedBox(height: 8),
        if (data.blocks.isEmpty)
          Text(
            'No blocks were planned.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          )
        else
          for (final block in data.blocks)
            _blockTile(context, block, categoriesById[block.categoryId], isPast),
      ],
    );
  }

  Widget _blockTile(
    BuildContext context,
    Block block,
    Category? category,
    bool isPast,
  ) {
    final scheme = Theme.of(context).colorScheme;
    var style = BlockStatusStyle.of(context, block.status);
    final unfinished =
        block.status == BlockStatus.pending ||
        block.status == BlockStatus.active ||
        block.status == BlockStatus.paused;
    // On a past day, a block that never finished is simply "not done".
    if (isPast && unfinished) {
      style = BlockStatusStyle(
        color: scheme.onSurfaceVariant,
        icon: Icons.radio_button_unchecked,
        label: 'Not done',
      );
    }

    final lines = <String>[
      'Planned ${_clock(block.plannedStart)}–${_clock(block.plannedEnd)} · '
          '${block.plannedDurationMinutes} min',
      if (block.actualStart != null)
        'Started ${_clock(block.actualStart)}'
            '${block.actualEnd == null ? '' : ' · ended ${_clock(block.actualEnd)}'}',
      if (block.recordedSeconds >= 60)
        '${block.recordedSeconds ~/ 60} min on timer',
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(style.icon, color: style.color),
        title: Text('${category?.icon ?? ''} ${block.title}'.trim()),
        subtitle: Text(lines.join('\n')),
        isThreeLine: lines.length > 2,
        trailing: Text(
          style.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: style.color,
          ),
        ),
      ),
    );
  }
}
