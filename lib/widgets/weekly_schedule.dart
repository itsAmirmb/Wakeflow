import 'package:flutter/material.dart';

import '../models/commitment.dart';

/// Row order of the week: Saturday first (DateTime.weekday values).
const List<int> kScheduleWeekdays = [6, 7, 1, 2, 3, 4, 5];

/// Display-only weekly timetable of fixed commitments: one row per day, a
/// shared hour axis across, and each commitment drawn at its real time.
/// Overlapping commitments of one day stack in lanes.
///
/// Weekly commitments appear on their weekdays; one-off commitments appear
/// only when their date falls in the week of [weekOf].
class WeeklyScheduleView extends StatelessWidget {
  final List<Commitment> commitments;

  /// Any date inside the week to show.
  final DateTime weekOf;

  /// Weekday (1 = Monday ... 7 = Sunday) whose row is emphasised.
  final int? highlightWeekday;

  /// Smaller blocks and a single line per commitment, for embedding.
  final bool compact;

  const WeeklyScheduleView({
    super.key,
    required this.commitments,
    required this.weekOf,
    this.highlightWeekday,
    this.compact = false,
  });

  static const double _labelWidth = 44;
  static const double _headerHeight = 24;

  /// Lane (stack row) for each entry, given entries sorted by start time.
  static List<int> _lanes(List<Commitment> sorted) {
    final laneEnds = <int>[];
    final lanes = <int>[];
    for (final c in sorted) {
      var lane = laneEnds.indexWhere((end) => end <= c.startMinutes);
      if (lane == -1) {
        laneEnds.add(c.endMinutes);
        lane = laneEnds.length - 1;
      } else {
        laneEnds[lane] = c.endMinutes;
      }
      lanes.add(lane);
    }
    return lanes;
  }

  @override
  Widget build(BuildContext context) {
    final offset = (weekOf.weekday - DateTime.saturday) % 7;
    final weekStart = DateTime(weekOf.year, weekOf.month, weekOf.day - offset);

    final days = <_DayData>[];
    for (var i = 0; i < 7; i++) {
      final date = DateTime(weekStart.year, weekStart.month, weekStart.day + i);
      final entries = commitments.where((c) => c.occursOn(date)).toList()
        ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
      days.add(_DayData(date.weekday, entries, _lanes(entries)));
    }

    final all = [for (final d in days) ...d.entries];
    if (all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No commitments this week.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Hour axis covering every commitment, at least four hours wide.
    final startHour = all
        .map((c) => c.startMinutes ~/ 60)
        .reduce((a, b) => a < b ? a : b);
    var endHour = all
        .map((c) => (c.endMinutes + 59) ~/ 60)
        .reduce((a, b) => a > b ? a : b);
    if (endHour - startHour < 4) endHour = startHour + 4;
    if (endHour > 24) endHour = 24;
    final hours = (endHour - startHour).clamp(1, 24);

    // Wider hours and taller lanes so titles can wrap onto two lines; when
    // the view has spare width the hours stretch to fill it (no empty gap).
    final baseHourWidth = compact ? 64.0 : 80.0;
    final laneHeight = compact ? 38.0 : 44.0;
    double rowHeight(_DayData d) {
      final lanes = d.lanes.isEmpty ? 1 : d.lanes.reduce((a, b) => a > b ? a : b) + 1;
      return lanes * laneHeight + 8;
    }

    final scheme = Theme.of(context).colorScheme;
    final lineColor = scheme.outlineVariant;

    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxWidth - _labelWidth;
      final hourWidth =
          available.isFinite && available / hours > baseHourWidth
          ? available / hours
          : baseHourWidth;
      final timelineWidth = hours * hourWidth;
      return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Column(
            children: [
              const SizedBox(height: _headerHeight),
              for (final d in days)
                Container(
                  height: rowHeight(d),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: lineColor)),
                  ),
                  child: Text(
                    Commitment.weekdayNames[d.weekday]!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: d.weekday == highlightWeekday
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: d.weekday == highlightWeekday
                          ? scheme.primary
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: timelineWidth,
              child: Column(
                children: [
                  SizedBox(
                    height: _headerHeight,
                    child: Row(
                      children: [
                        for (var h = startHour; h < endHour; h++)
                          SizedBox(
                            width: hourWidth,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  h.toString().padLeft(2, '0'),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final d in days)
                    _DayRow(
                      data: d,
                      startHour: startHour,
                      hours: hours,
                      hourWidth: hourWidth,
                      laneHeight: laneHeight,
                      height: rowHeight(d),
                      highlighted: d.weekday == highlightWeekday,
                      compact: compact,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    });
  }
}

class _DayData {
  final int weekday;
  final List<Commitment> entries;
  final List<int> lanes;
  const _DayData(this.weekday, this.entries, this.lanes);
}

class _DayRow extends StatelessWidget {
  final _DayData data;
  final int startHour;
  final int hours;
  final double hourWidth;
  final double laneHeight;
  final double height;
  final bool highlighted;
  final bool compact;

  const _DayRow({
    required this.data,
    required this.startHour,
    required this.hours,
    required this.hourWidth,
    required this.laneHeight,
    required this.height,
    required this.highlighted,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = <(Color, Color)>[
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    ];

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: highlighted ? scheme.primaryContainer.withAlpha(60) : null,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              for (var h = 0; h < hours; h++)
                Container(
                  width: hourWidth,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                ),
            ],
          ),
          for (var i = 0; i < data.entries.length; i++)
            _block(context, data.entries[i], data.lanes[i], palette),
        ],
      ),
    );
  }

  Widget _block(
    BuildContext context,
    Commitment c,
    int lane,
    List<(Color, Color)> palette,
  ) {
    // Same title, same colour: derived from the characters, not hashCode.
    final colors = palette[c.title.codeUnits.fold<int>(0, (a, b) => a + b) %
        palette.length];
    final left = (c.startMinutes - startHour * 60) / 60 * hourWidth;
    final width = ((c.endMinutes - c.startMinutes) / 60 * hourWidth - 2)
        .clamp(18.0, double.infinity);
    final time = '${Commitment.hm(c.startMinutes)}–${Commitment.hm(c.endMinutes)}';
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colors.$2,
    );

    return Positioned(
      left: left,
      top: 4 + lane * laneHeight,
      width: width,
      height: laneHeight - 2,
      child: Tooltip(
        message: '${c.title}\n$time${c.isRecurring ? '' : '\nOne-off'}',
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: colors.$1,
            borderRadius: BorderRadius.circular(6),
            // One-off events get an outline to tell them from weekly ones.
            border: c.isRecurring
                ? null
                : Border.all(color: colors.$2.withAlpha(140)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.title,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(fontWeight: FontWeight.w600, height: 1.1),
              ),
              if (!compact)
                Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
