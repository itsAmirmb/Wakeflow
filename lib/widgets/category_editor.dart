import 'package:flutter/material.dart';

import '../models/category.dart';

/// One expandable row per category: enable toggle plus sliders for
/// minimum/maximum per day and the fixed block size. The share of the day
/// is set on the timeline bar (see CategoryTimelineBar). Shared by the
/// Settings tab and the Start Day screen so both edit categories the same way.
class CategoryEditorTile extends StatelessWidget {
  final Category category;
  final ValueChanged<Category> onChanged;

  /// When set, a Delete button is shown (Settings only).
  final VoidCallback? onDelete;

  const CategoryEditorTile({
    super.key,
    required this.category,
    required this.onChanged,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Text(category.icon, style: const TextStyle(fontSize: 22)),
      title: Text(category.name),
      subtitle: Text('${category.blockMinutes}m blocks'),
      trailing: Switch(
        value: category.enabled,
        onChanged: (value) => onChanged(category.copyWith(enabled: value)),
      ),
      children: [
        LabeledSlider(
          label: 'Minimum per day',
          value: category.minimumMinutes.toDouble(),
          min: 0,
          max: 180,
          divisions: 36,
          formatValue: (v) => '${v.round()}m',
          // Raising the minimum past the maximum lifts the maximum with it.
          onChangeEnd: (value) => onChanged(
            category.copyWith(
              minimumMinutes: value.round(),
              maximumMinutes:
                  category.maximumMinutes != null &&
                      value.round() > category.maximumMinutes!
                  ? value.round()
                  : null,
            ),
          ),
        ),
        LabeledSlider(
          label: 'Maximum per day',
          value: (category.maximumMinutes ?? 0).toDouble(),
          min: 0,
          max: 480,
          divisions: 32,
          formatValue: (v) => v.round() == 0 ? 'No limit' : '${v.round()}m',
          // 0 means no limit; otherwise never below the minimum.
          onChangeEnd: (value) => onChanged(
            value.round() == 0
                ? category.copyWith(clearMaximum: true)
                : category.copyWith(
                    maximumMinutes: value.round() < category.minimumMinutes
                        ? category.minimumMinutes
                        : value.round(),
                  ),
          ),
        ),
        LabeledSlider(
          label: 'Block size',
          value: category.blockMinutes.toDouble(),
          min: 15,
          max: 180,
          divisions: 33,
          formatValue: (v) => '${v.round()}m',
          onChangeEnd: (value) =>
              onChanged(category.copyWith(blockMinutes: value.round())),
        ),
        if (onDelete != null)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete category'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class LabeledSlider extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) formatValue;
  final ValueChanged<double> onChangeEnd;

  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.formatValue,
    required this.onChangeEnd,
  });

  @override
  State<LabeledSlider> createState() => LabeledSliderState();
}

class LabeledSliderState extends State<LabeledSlider> {
  late double _dragValue = widget.value;

  @override
  void didUpdateWidget(covariant LabeledSlider old) {
    super.didUpdateWidget(old);
    // Keep in sync if the category changes from elsewhere (e.g. the
    // enabled switch triggering a parent rebuild with fresh data).
    _dragValue = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.label, style: Theme.of(context).textTheme.bodySmall),
              Text(
                widget.formatValue(_dragValue),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Slider(
            value: _dragValue.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: widget.onChangeEnd,
          ),
        ],
      ),
    );
  }
}
