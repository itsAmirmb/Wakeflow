import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/theme_controller.dart';
import '../widgets/category_editor.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.loadCategories,
    this.loadSettings,
    this.persistSettings,
    this.persistCategory,
    this.createCategory,
    this.deleteCategory,
    this.scheduleWakeReminder,
  });

  final Future<List<Category>> Function()? loadCategories;
  final Future<AppSettings> Function()? loadSettings;
  final Future<void> Function(AppSettings)? persistSettings;
  final Future<void> Function(Category)? persistCategory;
  final Future<void> Function(Category)? createCategory;
  final Future<void> Function(String id)? deleteCategory;
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

  Future<void> _addCategory() async {
    final categories = _categories;
    if (categories == null || _saving) return;
    final created = await showDialog<Category>(
      context: context,
      builder: (_) => _NewCategoryDialog(existing: categories),
    );
    if (created == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await (widget.createCategory ?? DatabaseService.instance.saveCategory)(
        created,
      );
      if (!mounted) return;
      setState(() => _categories = [...categories, created]);
    } catch (_) {
      _showError('Could not add the category. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCategory(Category category) async {
    final categories = _categories;
    if (categories == null || _saving) return;
    // Routines need at least one enabled category to plan with.
    final othersEnabled = categories.any(
      (c) => c.id != category.id && c.enabled,
    );
    if (!othersEnabled) {
      _showError('Keep at least one other enabled category.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${category.name}?'),
        content: const Text(
          'Past days keep their history and stats. Blocks already planned '
          'today stay until you Distill or re-plan at a checkpoint. '
          'To keep the category but stop planning it, switch it off instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await (widget.deleteCategory ?? DatabaseService.instance.deleteCategory)(
        category.id,
      );
      if (!mounted) return;
      setState(
        () => _categories = categories.where((c) => c.id != category.id).toList(),
      );
    } catch (_) {
      _showError('Could not delete the category. Please try again.');
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

  Future<void> _addCheckpointTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (!mounted || picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    final times = {..._settings.checkpointMinutesOfDay, minute}.toList()
      ..sort();
    await _saveSettings(_settings.copyWith(checkpointMinutesOfDay: times));
  }

  Future<void> _pickDayReset() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settings.dayResetMinutes ~/ 60,
        minute: _settings.dayResetMinutes % 60,
      ),
    );
    if (picked == null || !mounted) return;
    _saveSettings(
      _settings.copyWith(dayResetMinutes: picked.hour * 60 + picked.minute),
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
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Checkpoint reminders'),
            subtitle: const Text('Fixed times of day'),
            trailing: IconButton(
              tooltip: 'Add checkpoint time',
              onPressed: _addCheckpointTime,
              icon: const Icon(Icons.add),
            ),
          ),
          if (_settings.checkpointMinutesOfDay.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('No checkpoint times selected.'),
            ),
          ..._settings.checkpointMinutesOfDay.map((minute) {
            final time = TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
            return ListTile(
              title: Text(time.format(context)),
              trailing: IconButton(
                tooltip: 'Remove checkpoint time',
                key: ValueKey('remove-checkpoint-$minute'),
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _saveSettings(
                  _settings.copyWith(
                    checkpointMinutesOfDay: _settings.checkpointMinutesOfDay
                        .where((value) => value != minute)
                        .toList(),
                  ),
                ),
              ),
            );
          }),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Schedule updates when you open Today. Reminders only occur '
              'between wake time and the routine deadline and ask you to open '
              'Today to review your progress. Delivery may be delayed without '
              'exact-alarm access.',
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
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Distillation: keep progress'),
            subtitle: Text(
              _settings.distillKeepValue == 0
                  ? 'Any unfinished block with progress is kept as a partial session'
                  : 'Unfinished blocks with at least ${_settings.distillKeepMode == DistillKeepMode.minutes ? '${_settings.distillKeepValue} min' : '${_settings.distillKeepValue}% of the block'}'
                      ' done are kept as partial sessions; the rest are discarded',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: SegmentedButton<DistillKeepMode>(
              segments: const [
                ButtonSegment(
                  value: DistillKeepMode.minutes,
                  label: Text('Minutes'),
                ),
                ButtonSegment(
                  value: DistillKeepMode.percent,
                  label: Text('Percent'),
                ),
              ],
              selected: {_settings.distillKeepMode},
              onSelectionChanged: (selection) => _saveSettings(
                _settings.copyWith(
                  distillKeepMode: selection.first,
                  // Ranges differ, so start from a sensible default.
                  distillKeepValue:
                      selection.first == DistillKeepMode.minutes ? 5 : 20,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: _settings.distillKeepValue.toDouble(),
              min: 0,
              max: _settings.distillKeepMode == DistillKeepMode.minutes
                  ? 60
                  : 100,
              divisions: _settings.distillKeepMode == DistillKeepMode.minutes
                  ? 60
                  : 20,
              label: _settings.distillKeepMode == DistillKeepMode.minutes
                  ? '${_settings.distillKeepValue}m'
                  : '${_settings.distillKeepValue}%',
              onChanged: (value) => setState(
                () => _settings = _settings.copyWith(
                  distillKeepValue: value.round(),
                ),
              ),
              onChangeEnd: (value) => _saveSettings(
                _settings.copyWith(distillKeepValue: value.round()),
              ),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.event_repeat),
            title: const Text('New day starts at'),
            subtitle: const Text(
              'Your routine resets at this time. If it is still unfinished, '
              'it carries over until you finish it or Distill.',
            ),
            trailing: Text(
              TimeOfDay(
                hour: _settings.dayResetMinutes ~/ 60,
                minute: _settings.dayResetMinutes % 60,
              ).format(context),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            onTap: _pickDayReset,
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Categories',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Add category',
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          ...categories.map(
            (category) => CategoryEditorTile(
              key: ValueKey(category.id),
              category: category,
              onChanged: _saveCategory,
              onDelete: () => _deleteCategory(category),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Name + emoji for a new category; everything else starts at neutral
/// defaults and is tuned in the category's own tile afterwards.
class _NewCategoryDialog extends StatefulWidget {
  final List<Category> existing;

  const _NewCategoryDialog({required this.existing});

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _icon = TextEditingController(text: '📌');

  @override
  void dispose() {
    _name.dispose();
    _icon.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Enter a name';
    final taken = widget.existing.any(
      (c) => c.name.trim().toLowerCase() == name.toLowerCase(),
    );
    return taken ? 'A category with this name already exists' : null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final icon = _icon.text.trim();
    final nextPriority = widget.existing.fold<int>(
          0,
          (max, c) => c.priority > max ? c.priority : max,
        ) +
        1;
    Navigator.pop(
      context,
      Category(
        id: 'cat_${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim(),
        // One emoji only; the row layout assumes a single glyph.
        icon: icon.isEmpty ? '📌' : icon.characters.first,
        percentage: 0.2,
        minimumMinutes: 0,
        preferredBlockMinMinutes: 30,
        preferredBlockMaxMinutes: 90,
        priority: nextPriority,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New category'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              maxLength: 24,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: _validateName,
              onFieldSubmitted: (_) => _submit(),
            ),
            TextFormField(
              controller: _icon,
              decoration: const InputDecoration(
                labelText: 'Emoji',
                helperText: 'Optional',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
