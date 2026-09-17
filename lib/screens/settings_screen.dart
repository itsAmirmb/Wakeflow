import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Category>? _categories;
  AppSettings _settings = const AppSettings();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final categories = await DatabaseService.instance.getCategories();
    final settings = await DatabaseService.instance.getSettings();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _settings = settings;
    });
  }

  Future<void> _saveSettings(AppSettings settings) async {
    await DatabaseService.instance.saveSettings(settings);
    // Re-schedule the daily reminder immediately so a time change
    // takes effect without waiting for the next app restart.
    await NotificationService.instance.scheduleWakeReminder(
      hour: settings.wakeReminderHour,
      minute: settings.wakeReminderMinute,
    );
    setState(() => _settings = settings);
  }

  Future<void> _saveCategory(Category category) async {
    await DatabaseService.instance.updateCategory(category);
    setState(() {
      _categories = _categories!
          .map((c) => c.id == category.id ? category : c)
          .toList();
    });
  }

  Future<void> _pickWakeReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settings.wakeReminderHour,
        minute: _settings.wakeReminderMinute,
      ),
    );
    if (picked == null) return;
    await _saveSettings(_settings.copyWith(
      wakeReminderHour: picked.hour,
      wakeReminderMinute: picked.minute,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    if (categories == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('General', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Wake reminder'),
          subtitle: Text(
            TimeOfDay(
              hour: _settings.wakeReminderHour,
              minute: _settings.wakeReminderMinute,
            ).format(context),
          ),
          onTap: _pickWakeReminderTime,
        ),
        ListTile(
          leading: const Icon(Icons.space_bar),
          title: const Text('Buffer between blocks'),
          subtitle: Text('${_settings.bufferMinutes} minutes'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: _settings.bufferMinutes.toDouble(),
            min: 0,
            max: 30,
            divisions: 30,
            label: '${_settings.bufferMinutes}m',
            onChanged: (value) {
              // Live-update the label while dragging; persist on release
              // (onChangeEnd) so we're not hitting the DB every pixel.
              setState(() => _settings = _settings.copyWith(bufferMinutes: value.round()));
            },
            onChangeEnd: (value) => _saveSettings(_settings.copyWith(bufferMinutes: value.round())),
          ),
        ),
        const Divider(height: 32),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('Categories', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ...categories.map(
          (category) => _CategoryTile(
            category: category,
            onChanged: _saveCategory,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// One expandable settings row per category: enable toggle plus
/// sliders for percentage, minimum duration, and preferred block size.
class _CategoryTile extends StatelessWidget {
  final Category category;
  final ValueChanged<Category> onChanged;

  const _CategoryTile({required this.category, required this.onChanged});

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
        _LabeledSlider(
          label: 'Percentage',
          value: category.percentage * 100,
          min: 0,
          max: 100,
          divisions: 20,
          formatValue: (v) => '${v.round()}%',
          onChangeEnd: (value) =>
              onChanged(category.copyWith(percentage: value / 100)),
        ),
        _LabeledSlider(
          label: 'Minimum duration',
          value: category.minimumMinutes.toDouble(),
          min: 0,
          max: 180,
          divisions: 36,
          formatValue: (v) => '${v.round()}m',
          onChangeEnd: (value) =>
              onChanged(category.copyWith(minimumMinutes: value.round())),
        ),
        _LabeledSlider(
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
        _LabeledSlider(
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

class _LabeledSlider extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) formatValue;
  final ValueChanged<double> onChangeEnd;

  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.formatValue,
    required this.onChangeEnd,
  });

  @override
  State<_LabeledSlider> createState() => _LabeledSliderState();
}

class _LabeledSliderState extends State<_LabeledSlider> {
  late double _dragValue = widget.value;

  @override
  void didUpdateWidget(covariant _LabeledSlider old) {
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
              Text(widget.formatValue(_dragValue), style: Theme.of(context).textTheme.bodySmall),
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
