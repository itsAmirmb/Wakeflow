import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.loadCategories,
    this.loadSettings,
    this.persistSettings,
    this.persistCategory,
    this.scheduleWakeReminder,
  });

  final Future<List<Category>> Function()? loadCategories;
  final Future<AppSettings> Function()? loadSettings;
  final Future<void> Function(AppSettings)? persistSettings;
  final Future<void> Function(Category)? persistCategory;
  final Future<void> Function(int hour, int minute)? scheduleWakeReminder;

  static bool wakeTimeChanged(AppSettings before, AppSettings after) =>
      before.wakeReminderHour != after.wakeReminderHour ||
      before.wakeReminderMinute != after.wakeReminderMinute;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Category>? _categories;
  AppSettings _settings = const AppSettings();
  AppSettings _persistedSettings = const AppSettings();
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loadError = null);
    try {
      final categories =
          await (widget.loadCategories ??
              DatabaseService.instance.getCategories)();
      final settings =
          await (widget.loadSettings ?? DatabaseService.instance.getSettings)();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _settings = _persistedSettings = settings;
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Could not load settings.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveSettings(AppSettings settings) async {
    if (!mounted || _saving) return;
    final previous = _persistedSettings;
    final reschedule = SettingsScreen.wakeTimeChanged(previous, settings);
    setState(() => _saving = true);
    try {
      try {
        await (widget.persistSettings ?? DatabaseService.instance.saveSettings)(
          settings,
        );
      } catch (_) {
        if (mounted) setState(() => _settings = previous);
        ThemeController.instance.setFromStored(previous.themeMode);
        _showError('Could not save settings. Please try again.');
        return;
      }
      _persistedSettings = settings;
      ThemeController.instance.setFromStored(settings.themeMode);
      if (mounted) setState(() => _settings = settings);
      // A scheduling failure must NOT roll back the UI after a successful DB
      // write. Keep the saved setting and report the partial failure honestly.
      if (reschedule) {
        try {
          final schedule = widget.scheduleWakeReminder;
          if (schedule != null) {
            await schedule(
              settings.wakeReminderHour,
              settings.wakeReminderMinute,
            );
          } else {
            await NotificationService.instance.scheduleWakeReminder(
              hour: settings.wakeReminderHour,
              minute: settings.wakeReminderMinute,
            );
          }
        } catch (_) {
          _showError(
            'Settings saved, but the reminder could not be scheduled. '
            'Check notification permissions and reopen the app to retry.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    if (_saving) return;
    ThemeController.instance.mode.value = mode;
    await _saveSettings(
      _settings.copyWith(themeMode: ThemeController.toStored(mode)),
    );
  }

  Future<void> _saveCategory(Category category) async {
    if (!mounted || _saving) return;
    setState(() => _saving = true);
    try {
      await (widget.persistCategory ?? DatabaseService.instance.updateCategory)(
        category,
      );
      if (!mounted) return;
      setState(() {
        _categories = _categories!
            .map((c) => c.id == category.id ? category : c)
            .toList();
      });
    } catch (_) {
      _showError('Could not save category. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickWakeReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settings.wakeReminderHour,
        minute: _settings.wakeReminderMinute,
      ),
    );
    if (!mounted || picked == null) return;
    await _saveSettings(
      _settings.copyWith(
        wakeReminderHour: picked.hour,
        wakeReminderMinute: picked.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    if (categories == null) {
      if (_loadError != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return AbsorbPointer(
      absorbing: _saving,
      child: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'General',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.dark_mode_outlined),
                const SizedBox(width: 12),
                const Text('Theme'),
                const Spacer(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {ThemeController.instance.mode.value},
              onSelectionChanged: (selection) => _setThemeMode(selection.first),
            ),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Next occurrence only, renewed when you open the app or '
              'change the wake time. Daily reminders while the app stays closed '
              'are not supported yet. Reopen after changing timezones. '
              'Without exact-alarm access, delivery may be delayed.',
            ),
          ),
          if (_saving) const LinearProgressIndicator(),
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
                setState(
                  () => _settings = _settings.copyWith(
                    bufferMinutes: value.round(),
                  ),
                );
              },
              onChangeEnd: (value) => _saveSettings(
                _settings.copyWith(bufferMinutes: value.round()),
              ),
            ),
          ),
          const Divider(height: 32),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Categories',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ...categories.map(
            (category) =>
                _CategoryTile(category: category, onChanged: _saveCategory),
          ),
          const SizedBox(height: 24),
        ],
      ),
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
