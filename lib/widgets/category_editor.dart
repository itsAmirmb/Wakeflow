import 'package:flutter/material.dart';

import '../models/category.dart';

/// One expandable row per category: enable toggle plus sliders for
/// percentage, minimum duration, and preferred block size. Shared by the
/// Settings tab and the Start Day screen so both edit categories the same way.
class CategoryEditorTile extends StatelessWidget {
  final Category category;
  final ValueChanged<Category> onChanged;

  const CategoryEditorTile({super.key, required this.category, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Text(category.icon, style: const TextStyle(fontSize: 22)),
      title: Text(category.name),
      subtitle: Text(
        '${(category.percentage * 100).round()}% · min ${category.minimumMinutes}m · '
        'block ${category.preferredBlockMinMinutes}-${category.preferredBlockMaxMinutes}m',
      ),
      trailing: Switch(
        value: category.enabled,
        onChanged: (value) => onChanged(category.copyWith(enabled: value)),
      ),
      children: [
        LabeledSlider(
          label: 'Percentage',
          value: category.percentage * 100,
          min: 0,
          max: 100,
          divisions: 20,
          formatValue: (v) => '${v.round()}%',
          onChangeEnd: (value) =>
              onChanged(category.copyWith(percentage: value / 100)),
        ),
        LabeledSlider(
          label: 'Minimum duration',
          value: category.minimumMinutes.toDouble(),
          min: 0,
          max: 180,
          divisions: 36,
          formatValue: (v) => '${v.round()}m',
          onChangeEnd: (value) =>
              onChanged(category.copyWith(minimumMinutes: value.round())),
        ),
        LabeledSlider(
          label: 'Preferred block — min',
          value: category.preferredBlockMinMinutes.toDouble(),
          min: 15,
          max: 180,
          divisions: 33,
          formatValue: (v) => '${v.round()}m',
          onChangeEnd: (value) => onChanged(
            category.copyWith(preferredBlockMinMinutes: value.round()),
          ),
        ),
        LabeledSlider(
          label: 'Preferred block — max',
          value: category.preferredBlockMaxMinutes.toDouble(),
          min: 15,
          max: 240,
          divisions: 45,
          formatValue: (v) => '${v.round()}m',
          onChangeEnd: (value) => onChanged(
            category.copyWith(preferredBlockMaxMinutes: value.round()),
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
