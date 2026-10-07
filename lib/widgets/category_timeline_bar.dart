import 'package:flutter/material.dart';

import '../models/category.dart';

/// Fixed palette; a category keeps its colour for as long as its position in
/// the list does, so toggling another category never recolours it.
const List<Color> kCategoryColors = [
  Color(0xFF4C8DF6),
  Color(0xFFF2994A),
  Color(0xFF27AE60),
  Color(0xFF9B51E0),
  Color(0xFFEB5757),
  Color(0xFF2D9CDB),
  Color(0xFFE0A800),
  Color(0xFF8D6E63),
];

Color categoryColor(int index) =>
    kCategoryColors[index % kCategoryColors.length];

/// One bar for the whole day: every enabled category is a coloured segment,
/// and dragging the line between two segments moves time from one category
/// to the other. The shares always add up to 100%.
class CategoryTimelineBar extends StatefulWidget {
  /// All categories in plan order (disabled ones are not drawn).
  final List<Category> categories;

  /// Called once per finished drag (or accessibility nudge) with the full
  /// list, in the same order, carrying the new percentages.
  final ValueChanged<List<Category>> onChanged;

  const CategoryTimelineBar({
    super.key,
    required this.categories,
    required this.onChanged,
  });

  @override
  State<CategoryTimelineBar> createState() => _CategoryTimelineBarState();
}

class _CategoryTimelineBarState extends State<CategoryTimelineBar> {
  static const int _minPoints = 1;
  static const double _barHeight = 56;
  static const double _handleWidth = 32;

  // Live values while a handle is dragged; null otherwise.
  List<int>? _dragPoints;
  List<int>? _dragStart;
  double _dragAccumulated = 0;

  List<int> get _visible => [
    for (var i = 0; i < widget.categories.length; i++)
      if (widget.categories[i].enabled) i,
  ];

  /// Whole percent points per visible category, normalised to exactly 100
  /// (largest-remainder rounding), whatever the stored percentages sum to.
  List<int> _points(List<int> visible) {
    if (visible.isEmpty) return const [];
    var weights = [for (final i in visible) widget.categories[i].percentage];
    if (weights.fold<double>(0, (a, b) => a + b) <= 0) {
      weights = List<double>.filled(visible.length, 1);
    }
    final sum = weights.fold<double>(0, (a, b) => a + b);
    final raw = [for (final w in weights) w / sum * 100];
    final result = [for (final r in raw) r.floor()];
    var rest = 100 - result.fold<int>(0, (a, b) => a + b);
    final order = [for (var i = 0; i < raw.length; i++) i]
      ..sort((a, b) => (raw[b] - result[b]).compareTo(raw[a] - result[a]));
    for (var k = 0; rest > 0 && k < order.length; k++, rest--) {
      result[order[k]]++;
    }
    return result;
  }

  void _commit(List<int> visible, List<int> points) {
    final updated = List<Category>.of(widget.categories);
    for (var j = 0; j < visible.length; j++) {
      updated[visible[j]] = updated[visible[j]].copyWith(
        percentage: points[j] / 100,
      );
    }
    widget.onChanged(updated);
  }

  /// Moves [boundary] (between visible segment boundary and boundary + 1) so
  /// the left one becomes [newLeft] points; null when not allowed.
  List<int>? _moved(List<int> points, int boundary, int newLeft) {
    final pair = points[boundary] + points[boundary + 1];
    if (pair < 2 * _minPoints) return null;
    final left = newLeft.clamp(_minPoints, pair - _minPoints);
    final next = List<int>.of(points);
    next[boundary] = left;
    next[boundary + 1] = pair - left;
    return next;
  }

  void _dragBegin(List<int> points) {
    _dragStart = List<int>.of(points);
    _dragPoints = List<int>.of(points);
    _dragAccumulated = 0;
  }

  void _dragUpdate(int boundary, double dx, double barWidth) {
    final start = _dragStart;
    if (start == null || barWidth <= 0) return;
    _dragAccumulated += dx;
    final shift = (_dragAccumulated / barWidth * 100).round();
    final next = _moved(start, boundary, start[boundary] + shift);
    if (next != null) setState(() => _dragPoints = next);
  }

  void _dragEnd(List<int> visible) {
    final points = _dragPoints;
    setState(() {
      _dragPoints = null;
      _dragStart = null;
    });
    if (points != null) _commit(visible, points);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    if (visible.isEmpty) {
      return Text(
        'Enable a category to plan time.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    final points = _dragPoints ?? _points(visible);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            var cumulative = 0;
            final handles = <Widget>[];
            for (var j = 0; j < visible.length - 1; j++) {
              cumulative += points[j];
              handles.add(
                _handle(
                  context,
                  boundary: j,
                  left: width * cumulative / 100 - _handleWidth / 2,
                  barWidth: width,
                  visible: visible,
                  points: points,
                ),
              );
            }
            return SizedBox(
              height: _barHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        for (var j = 0; j < visible.length; j++)
                          _segment(
                            context,
                            index: visible[j],
                            width: width * points[j] / 100,
                            percent: points[j],
                          ),
                      ],
                    ),
                  ),
                  ...handles,
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (var j = 0; j < visible.length; j++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: categoryColor(visible[j]),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.categories[visible[j]].icon} '
                    '${widget.categories[visible[j]].name} · ${points[j]}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _segment(
    BuildContext context, {
    required int index,
    required double width,
    required int percent,
  }) {
    final color = categoryColor(index);
    final textColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Container(
      width: width,
      height: _barHeight,
      color: color,
      alignment: Alignment.center,
      child: width < 28
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.categories[index].icon,
                  style: const TextStyle(fontSize: 18),
                ),
                if (width >= 44)
                  Text(
                    '$percent%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _handle(
    BuildContext context, {
    required int boundary,
    required double left,
    required double barWidth,
    required List<int> visible,
    required List<int> points,
  }) {
    final a = widget.categories[visible[boundary]];
    final b = widget.categories[visible[boundary + 1]];
    void nudge(int step) {
      final next = _moved(points, boundary, points[boundary] + step);
      if (next != null) _commit(visible, next);
    }

    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: _handleWidth,
      child: Semantics(
        slider: true,
        label: 'Time split between ${a.name} and ${b.name}',
        value: '${a.name} ${points[boundary]}%, ${b.name} ${points[boundary + 1]}%',
        onIncrease: () => nudge(1),
        onDecrease: () => nudge(-1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _dragBegin(points),
          onHorizontalDragUpdate: (d) =>
              _dragUpdate(boundary, d.delta.dx, barWidth),
          onHorizontalDragEnd: (_) => _dragEnd(visible),
          onHorizontalDragCancel: () => _dragEnd(visible),
          child: Center(
            child: Container(
              width: 6,
              height: _barHeight - 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
