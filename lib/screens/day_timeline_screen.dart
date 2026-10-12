import 'dart:async';

import 'package:flutter/material.dart';

import '../models/block.dart';
import '../models/category.dart';
import '../models/commitment.dart';
import '../models/timeline_entry.dart';
import '../services/active_day.dart';
import '../services/database_service.dart';
import '../services/day_label.dart';
import '../services/day_timeline.dart';
import '../widgets/block_status_style.dart';

typedef _Loaded = ({
  String day,
  DateTime date,
  List<Block> blocks,
  Map<String, Category> categories,
  List<Commitment> commitments,
  List<int> checkpointMinutes,
  List<DateTime> reviewTimes,
  DateTime? wake,
  DateTime? dayEnd,
});

/// Everything planned for the day on one rail, in time order: wake time,
/// blocks, breaks, fixed commitments, checkpoints and the day target, with a
/// live "now" marker.
class DayTimelineScreen extends StatefulWidget {
  /// The day to show (yyyy-MM-dd); null means the current day.
  final String? day;

  const DayTimelineScreen({super.key, this.day});

  @override
  State<DayTimelineScreen> createState() => _DayTimelineScreenState();
}

class _DayTimelineScreenState extends State<DayTimelineScreen>
    with WidgetsBindingObserver {
  _Loaded? _data;
  bool _failed = false;
  DateTime _now = DateTime.now();
  Timer? _ticker;
  final GlobalKey _nowKey = GlobalKey();
  bool _scrolledToNow = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keeps the "now" marker and the due/upcoming states current.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final db = DatabaseService.instance;
      final now = DateTime.now();
      final day = widget.day ?? await ActiveDay.resolve(db, now);
      final blocks = await db.getBlocksForDay(day);
      final categories = await db.getCategories();
      final meta = await db.getDayMeta(day);
      // All of them: the timeline picks the ones inside the routine's span.
      final commitments = await db.getCommitments();
      final settings = await db.getSettings();
      final reviews = await db.getCheckpoints(day);

      DateTime? lastPlanned;
      for (final b in blocks) {
        final end = b.plannedEnd;
        if (end != null && (lastPlanned == null || end.isAfter(lastPlanned))) {
          lastPlanned = end;
        }
      }
      if (!mounted) return;
      setState(() {
        _now = now;
        _failed = false;
        _data = (
          day: day,
          date: DateTime.parse(day),
          blocks: blocks,
          categories: {for (final c in categories) c.id: c},
          commitments: commitments,
          checkpointMinutes: settings.checkpointMinutesOfDay,
          reviewTimes: [
            for (final r in reviews) DateTime.parse(r['reviewedAt'] as String),
          ],
          wake: meta?.$2,
          dayEnd: meta?.$3 ?? lastPlanned,
        );
      });
      _scheduleScrollToNow();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _scheduleScrollToNow() {
    if (_scrolledToNow) return;
    _scrolledToNow = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToNow());
  }

  void _jumpToNow() {
    final context = _nowKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.35,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timeline'),
        actions: [
          IconButton(
            tooltip: 'Jump to now',
            icon: const Icon(Icons.my_location),
            onPressed: data == null ? null : _jumpToNow,
          ),
        ],
      ),
      body: _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load the timeline.'),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _content(context, data)),
    );
  }

  Widget _content(BuildContext context, _Loaded data) {
    final scheme = Theme.of(context).colorScheme;
    final entries = DayTimeline.build(
      date: data.date,
      blocks: data.blocks,
      categories: data.categories,
      commitments: data.commitments,
      checkpointMinutes: data.checkpointMinutes,
      reviewTimes: data.reviewTimes,
      wake: data.wake,
      dayEnd: data.dayEnd,
      now: _now,
    );
    final real = entries.where((e) => e.kind != TimelineKind.now).toList();
    if (real.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              'Nothing planned for this day yet.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    final blocks = data.blocks
        .where((b) => b.status != BlockStatus.cancelled)
        .toList();
    final done = blocks
        .where(
          (b) =>
              b.status == BlockStatus.completed ||
              b.status == BlockStatus.partial,
        )
        .length;
    final upcoming = entries
        .where(
          (e) =>
              e.kind == TimelineKind.block &&
              e.blockStatus == BlockStatus.pending &&
              !e.start.isBefore(_now),
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatDayLabel(
                  data.day,
                  today: DayTimeline.dayKeyOf(_now),
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  '$done of ${blocks.length} blocks done',
                  if (upcoming.isNotEmpty)
                    'next: ${upcoming.first.title} at '
                        '${DayTimeline.clock(upcoming.first.start)}',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < entries.length; i++)
          _TimelineRow(
            key: entries[i].kind == TimelineKind.now ? _nowKey : null,
            entry: entries[i],
            now: _now,
            isFirst: i == 0,
            isLast: i == entries.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final TimelineEntry entry;
  final DateTime now;
  final bool isFirst;
  final bool isLast;

  const _TimelineRow({
    super.key,
    required this.entry,
    required this.now,
    required this.isFirst,
    required this.isLast,
  });

  static const double _timeWidth = 48;
  static const double _railWidth = 32;

  bool get _isPast {
    final end = entry.end ?? entry.start;
    return !end.isAfter(now);
  }

  bool get _isCurrent =>
      entry.end != null && !entry.start.isAfter(now) && entry.end!.isAfter(now);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (entry.kind == TimelineKind.now) return _nowRow(context, scheme);

    final look = _look(context, scheme);
    final lineColor = _isPast
        ? scheme.primary.withAlpha(110)
        : scheme.outlineVariant;
    final isBreak = entry.kind == TimelineKind.breakTime;

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: [
        DayTimeline.clock(entry.start),
        if (entry.end != null) 'to ${DayTimeline.clock(entry.end!)}',
        entry.title,
        if (look.status != null) look.status!,
        if (entry.detail != null) entry.detail!,
      ].join(', '),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _timeWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      DayTimeline.clock(entry.start),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: _isPast && !_isCurrent
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (entry.end != null && !isBreak)
                      Text(
                        DayTimeline.clock(entry.end!),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: _railWidth,
              child: Column(
                children: [
                  SizedBox(
                    height: 10,
                    child: isFirst
                        ? null
                        : Center(child: Container(width: 2, color: lineColor)),
                  ),
                  _dot(scheme, look, isBreak),
                  Expanded(
                    child: isLast
                        ? const SizedBox.shrink()
                        : Center(child: Container(width: 2, color: lineColor)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: isBreak
                    ? _breakContent(context, scheme)
                    : _card(context, scheme, look),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(ColorScheme scheme, _Look look, bool isBreak) {
    final size = isBreak ? 12.0 : 24.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surface,
        border: Border.all(color: look.color, width: 2),
      ),
      child: isBreak
          ? null
          : Icon(look.icon, size: 14, color: look.color),
    );
  }

  Widget _breakContent(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
      child: Text(
        '${entry.title} · ${entry.detail}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _card(BuildContext context, ColorScheme scheme, _Look look) {
    final text = Theme.of(context).textTheme;
    final emphasised = _isCurrent && entry.kind == TimelineKind.block ||
        entry.checkpointState == CheckpointState.due;
    final dim = _isPast &&
        !emphasised &&
        entry.checkpointState != CheckpointState.missed;
    final background = switch (entry.kind) {
      TimelineKind.commitment => scheme.tertiaryContainer.withAlpha(120),
      _ when emphasised => scheme.primaryContainer,
      _ => scheme.surfaceContainerHighest.withAlpha(140),
    };
    final plain = entry.kind == TimelineKind.wake ||
        entry.kind == TimelineKind.dayEnd;

    final titleStyle = text.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: dim ? scheme.onSurfaceVariant : null,
      decoration: entry.blockStatus == BlockStatus.skipped
          ? TextDecoration.lineThrough
          : null,
    );

    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: plain ? 4 : 12,
        vertical: plain ? 8 : 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.icon == null ? '' : '${entry.icon} '}${entry.title}',
                  style: titleStyle,
                ),
                if (entry.detail != null)
                  Text(
                    entry.detail!,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (look.status != null)
            Text(
              look.status!,
              style: text.labelMedium?.copyWith(color: look.color),
            ),
        ],
      ),
    );

    if (plain) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: content,
    );
  }

  Widget _nowRow(BuildContext context, ColorScheme scheme) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          SizedBox(
            width: _timeWidth,
            child: Text(
              DayTimeline.clock(now),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: _railWidth,
            child: Center(
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Text(
                  'NOW',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Divider(color: scheme.primary, thickness: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _Look _look(BuildContext context, ColorScheme scheme) {
    switch (entry.kind) {
      case TimelineKind.block:
        final style = BlockStatusStyle.of(context, entry.blockStatus!);
        return _Look(style.icon, style.color, style.label);
      case TimelineKind.checkpoint:
        return switch (entry.checkpointState!) {
          CheckpointState.reviewed => _Look(
            Icons.check_circle,
            scheme.primary,
            'Reviewed',
          ),
          CheckpointState.due => _Look(
            Icons.priority_high,
            scheme.error,
            'Due',
          ),
          CheckpointState.upcoming => _Look(
            Icons.flag_outlined,
            scheme.onSurfaceVariant,
            null,
          ),
          CheckpointState.missed => _Look(
            Icons.flag,
            scheme.onSurfaceVariant,
            'Missed',
          ),
        };
      case TimelineKind.commitment:
        return _Look(Icons.event_busy_outlined, scheme.tertiary, null);
      case TimelineKind.wake:
        return _Look(Icons.wb_sunny_outlined, scheme.onSurfaceVariant, null);
      case TimelineKind.dayEnd:
        return _Look(Icons.flag_outlined, scheme.onSurfaceVariant, null);
      case TimelineKind.breakTime:
        return _Look(Icons.circle, scheme.outline, null);
      case TimelineKind.now:
        return _Look(Icons.circle, scheme.primary, null);
    }
  }
}

class _Look {
  final IconData icon;
  final Color color;

  /// Short word shown next to the entry, so its state never depends on
  /// colour alone.
  final String? status;

  const _Look(this.icon, this.color, this.status);
}
