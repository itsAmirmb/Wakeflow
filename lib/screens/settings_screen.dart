import 'package:flutter/material.dart';

import '../models/alert_style.dart';
import '../models/category.dart';
import '../models/commitment.dart';
import '../models/app_settings.dart';
import '../services/alarm_sound.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/theme_controller.dart';
import '../widgets/category_editor.dart';
import '../widgets/commitment_editor.dart';
import '../services/day_key.dart';

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
  List<Commitment> _commitments = const [];
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
      // Commitments are optional extras: a failure here must not block the
      // rest of Settings.
      var commitments = <Commitment>[];
      try {
        commitments = await DatabaseService.instance.getCommitments();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _commitments = commitments;
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

  Future<void> _editCommitment(Commitment? existing) async {
    if (_saving) return;
    final result = await showCommitmentEditor(context, existing: existing);
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final db = DatabaseService.instance;
      if (result.deleted && existing != null) {
        await db.deleteCommitment(existing.id);
        if (!mounted) return;
        setState(
          () => _commitments = _commitments
              .where((c) => c.id != existing.id)
              .toList(),
        );
      } else if (result.saved != null) {
        final saved = result.saved!;
        await db.saveCommitment(saved);
        if (!mounted) return;
        setState(
          () => _commitments = [
            ..._commitments.where((c) => c.id != saved.id),
            saved,
          ],
        );
      }
    } catch (_) {
      _showError('Could not save the commitment. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleCommitment(Commitment commitment, bool enabled) async {
    if (_saving) return;
    final updated = commitment.copyWith(enabled: enabled);
    setState(() => _saving = true);
    try {
      await DatabaseService.instance.saveCommitment(updated);
      if (!mounted) return;
      setState(
        () => _commitments = [
          for (final c in _commitments) c.id == updated.id ? updated : c,
        ],
      );
    } catch (_) {
      _showError('Could not update the commitment. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _commitmentSubtitle(Commitment c) {
    final times =
        '${Commitment.hm(c.startMinutes)}–${Commitment.hm(c.endMinutes)}';
    if (!c.isRecurring) return '${c.date} · $times';
    // Same week order as the editor: it follows the locale.
    final first = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final days = [
      for (var i = 0; i < 7; i++)
        if (c.weekdays.contains((first + i) % 7 == 0 ? 7 : (first + i) % 7))
          Commitment.weekdayNames[(first + i) % 7 == 0 ? 7 : (first + i) % 7]!,
    ];
    return '${days.join(', ')} · $times';
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
          if (_saving) const LinearProgressIndicator(),
          const _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
          const _SectionHeader('Day'),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Wake reminder'),
            trailing: _ValueWithInfo(
              value: TimeOfDay(
                hour: _settings.wakeReminderHour,
                minute: _settings.wakeReminderMinute,
              ).format(context),
              infoTitle: 'Wake reminder',
              info:
                  'Scheduled for the next occurrence and renewed when you open '
                  'the app or change the time. Reopen the app after changing '
                  'time zones. Without exact-alarm access it may arrive late.',
            ),
            onTap: _pickWakeReminderTime,
          ),
          ListTile(
            leading: const Icon(Icons.event_repeat),
            title: const Text('New day starts at'),
            trailing: _ValueWithInfo(
              value: TimeOfDay(
                hour: _settings.dayResetMinutes ~/ 60,
                minute: _settings.dayResetMinutes % 60,
              ).format(context),
              infoTitle: 'New day starts at',
              info:
                  'Your routine resets at this time. If it is still '
                  'unfinished, it carries over until you finish it or distill.',
            ),
            onTap: _pickDayReset,
          ),
          _SectionHeader(
            'Fixed commitments',
            trailing: IconButton(
              tooltip: 'Add commitment',
              onPressed: () => _editCommitment(null),
              icon: const Icon(Icons.add),
            ),
          ),
          Builder(
            builder: (context) {
              // Single-day events in the past are history, not settings.
              final today = dayKey(DateTime.now());
              final shown =
                  _commitments
                      .where((c) => c.isRecurring || c.date!.compareTo(today) >= 0)
                      .toList()
                    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
              if (shown.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'None yet.',
                  ),
                );
              }
              return Column(
                children: [
                  for (final c in shown)
                    ListTile(
                      key: ValueKey('commitment-${c.id}'),
                      leading: Icon(c.isRecurring ? Icons.repeat : Icons.event),
                      title: Text(c.title),
                      subtitle: Text(_commitmentSubtitle(c)),
                      onTap: () => _editCommitment(c),
                      trailing: Switch(
                        value: c.enabled,
                        onChanged: (value) => _toggleCommitment(c, value),
                      ),
                    ),
                ],
              );
            },
          ),
          const _SectionHeader('Breaks'),
          _SliderTile(
            icon: Icons.space_bar,
            title: 'Short break',
            valueText: _settings.bufferMinutes == 0
                ? 'Off'
                : '${_settings.bufferMinutes} min',
            info: 'Timer that runs after a finished block when more blocks of '
                'the same category follow.',
            value: _settings.bufferMinutes.toDouble(),
            min: 0,
            max: 30,
            divisions: 30,
            onChanged: (value) => setState(
              () => _settings = _settings.copyWith(bufferMinutes: value.round()),
            ),
            onChangeEnd: (value) =>
                _saveSettings(_settings.copyWith(bufferMinutes: value.round())),
          ),
          _SliderTile(
            icon: Icons.weekend_outlined,
            title: 'Long break',
            valueText: _settings.longBreakMinutes == 0
                ? 'Off'
                : '${_settings.longBreakMinutes} min',
            info: 'Timer that runs after the last block of a category.',
            value: _settings.longBreakMinutes.toDouble().clamp(0, 90),
            min: 0,
            max: 90,
            divisions: 18,
            onChanged: (value) => setState(
              () => _settings = _settings.copyWith(
                longBreakMinutes: value.round(),
              ),
            ),
            onChangeEnd: (value) => _saveSettings(
              _settings.copyWith(longBreakMinutes: value.round()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Break-end alarm'),
            subtitle: Text(_settings.breakAlarmTitle ?? 'WakeFlow default'),
            trailing: _settings.breakAlarmUri == null
                ? null
                : IconButton(
                    tooltip: 'Use default',
                    icon: const Icon(Icons.restart_alt),
                    onPressed: () =>
                        _saveSettings(_settings.copyWith(clearBreakAlarm: true)),
                  ),
            onTap: () async {
              final picked = await AlarmSound.pickAlarm(
                current: _settings.breakAlarmUri,
              );
              if (picked == null || !mounted) return;
              await _saveSettings(
                _settings.copyWith(
                  breakAlarmUri: picked.uri,
                  breakAlarmTitle: picked.title,
                ),
              );
            },
          ),
          _SectionHeader(
            'Checkpoints',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _InfoButton(
                  title: 'Checkpoints',
                  text:
                      'At these times of day a reminder asks you to review your '
                      'progress in Today. They only occur between wake time and '
                      'the routine deadline, and stop once nothing is left to do.',
                ),
                IconButton(
                  tooltip: 'Add checkpoint time',
                  onPressed: _addCheckpointTime,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _settings.checkpointMinutesOfDay.isEmpty
                ? Text(
                    'No times set.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final minute in _settings.checkpointMinutesOfDay)
                        InputChip(
                          key: ValueKey('remove-checkpoint-$minute'),
                          label: Text(
                            TimeOfDay(
                              hour: minute ~/ 60,
                              minute: minute % 60,
                            ).format(context),
                          ),
                          deleteButtonTooltipMessage: 'Remove checkpoint time',
                          onDeleted: () => _saveSettings(
                            _settings.copyWith(
                              checkpointMinutesOfDay: _settings
                                  .checkpointMinutesOfDay
                                  .where((value) => value != minute)
                                  .toList(),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          _SliderTile(
            icon: Icons.science_outlined,
            title: 'Distill keeps progress of',
            valueText: _settings.distillKeepValue == 0
                ? 'Any'
                : _settings.distillKeepMode == DistillKeepMode.minutes
                ? '${_settings.distillKeepValue} min'
                : '${_settings.distillKeepValue}%',
            info:
                'When you distill, unfinished blocks with at least this much '
                'timer progress are kept as partial sessions; the rest are '
                'discarded.',
            value: _settings.distillKeepValue.toDouble(),
            min: 0,
            max: _settings.distillKeepMode == DistillKeepMode.minutes
                ? 60
                : 100,
            divisions: _settings.distillKeepMode == DistillKeepMode.minutes
                ? 60
                : 20,
            onChanged: (value) => setState(
              () => _settings = _settings.copyWith(
                distillKeepValue: value.round(),
              ),
            ),
            onChangeEnd: (value) => _saveSettings(
              _settings.copyWith(distillKeepValue: value.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
          const _SectionHeader('Notifications'),
          for (final event in AlertEvent.values)
            _AlertTile(
              key: ValueKey('alert-${event.name}'),
              event: event,
              style: _settings.alertFor(event),
              onChanged: (style) => _saveSettings(
                _settings.copyWith(alerts: {..._settings.alerts, event: style}),
              ),
            ),
          _SectionHeader(
            'Categories',
            trailing: IconButton(
              tooltip: 'Add category',
              onPressed: _addCategory,
              icon: const Icon(Icons.add),
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

/// Section title with an optional trailing action (e.g. an add button).
class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Explanations live behind this button instead of cluttering the list.
class _InfoButton extends StatelessWidget {
  final String title;
  final String text;

  const _InfoButton({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'About $title',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.info_outline, size: 20),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueWithInfo extends StatelessWidget {
  final String value;
  final String infoTitle;
  final String info;

  const _ValueWithInfo({
    required this.value,
    required this.infoTitle,
    required this.info,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        _InfoButton(title: infoTitle, text: info),
      ],
    );
  }
}

/// Title and current value on one line, slider below; optional info button.
class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String valueText;
  final String? info;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderTile({
    required this.icon,
    required this.title,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(valueText, style: Theme.of(context).textTheme.titleMedium),
              if (info != null) _InfoButton(title: title, text: info!),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
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
        blockMinutes: 45,
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

/// Alert style editor for one event: on/off, sound, vibration and whether the
/// sound repeats (alarm-like) until the notification is opened or dismissed.
class _AlertTile extends StatelessWidget {
  final AlertEvent event;
  final AlertStyle style;
  final ValueChanged<AlertStyle> onChanged;

  const _AlertTile({
    super.key,
    required this.event,
    required this.style,
    required this.onChanged,
  });

  static const _soundLabels = {
    AlertSound.standard: 'Default',
    AlertSound.alarm: 'Alarm',
    AlertSound.silent: 'Silent',
  };

  @override
  Widget build(BuildContext context) {
    final silent = style.sound == AlertSound.silent;
    return ExpansionTile(
      title: Text(event.label),
      subtitle: Text(
        !style.enabled
            ? 'Off'
            : '${_soundLabels[style.sound]}'
                  '${style.vibrate ? ' · vibrate' : ''}'
                  '${style.repeat && !silent ? ' · repeats' : ''}',
      ),
      trailing: Switch(
        value: style.enabled,
        onChanged: (value) => onChanged(style.copyWith(enabled: value)),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<AlertSound>(
            segments: [
              for (final sound in AlertSound.values)
                ButtonSegment(value: sound, label: Text(_soundLabels[sound]!)),
            ],
            selected: {style.sound},
            onSelectionChanged: (selection) =>
                onChanged(style.copyWith(sound: selection.first)),
          ),
        ),
        SwitchListTile(
          title: const Text('Vibrate'),
          value: style.vibrate,
          onChanged: (value) => onChanged(style.copyWith(vibrate: value)),
        ),
        SwitchListTile(
          title: const Text('Repeat (up to 3 min)'),
          value: style.repeat && !silent,
          onChanged: silent
              ? null
              : (value) => onChanged(style.copyWith(repeat: value)),
        ),
      ],
    );
  }
}
