import 'dart:async';

import 'package:flutter/material.dart';

import '../models/routine_target.dart';
import '../services/database_service.dart';
import '../services/day_mode_calculator.dart';
import '../services/greeting.dart';
import 'day_mode_screen.dart';

class WakeScreen extends StatefulWidget {
  const WakeScreen({super.key});

  @override
  State<WakeScreen> createState() => _WakeScreenState();
}

class _WakeScreenState extends State<WakeScreen> {
  RoutineTargetMode _mode = RoutineTargetMode.targetTime;
  TimeOfDay _targetTime = const TimeOfDay(hour: 18, minute: 30);
  int _targetDurationMinutes = 8 * 60;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLastTarget());
  }

  RoutineTarget get _target {
    return _mode == RoutineTargetMode.targetTime
        ? RoutineTarget.time(hour: _targetTime.hour, minute: _targetTime.minute)
        : RoutineTarget.duration(minutes: _targetDurationMinutes);
  }

  /// Starts from the last target that was used.
  Future<void> _loadLastTarget() async {
    try {
      final settings = await DatabaseService.instance.getSettings();
      if (!mounted) return;
      setState(() {
        _mode = settings.targetMode;
        _targetTime = TimeOfDay(
          hour: settings.targetTimeMinutes ~/ 60,
          minute: settings.targetTimeMinutes % 60,
        );
        _targetDurationMinutes = settings.targetDurationMinutes;
      });
    } catch (_) {
      // Defaults are fine; remembering is only a convenience.
    }
  }

  Future<void> _saveTarget() async {
    try {
      final db = DatabaseService.instance;
      final current = await db.getSettings();
      await db.saveSettings(
        current.copyWith(
          targetMode: _mode,
          targetTimeMinutes: _targetTime.hour * 60 + _targetTime.minute,
          targetDurationMinutes: _targetDurationMinutes,
        ),
      );
    } catch (_) {
      // Never block starting the day because the choice could not be saved.
    }
  }

  Future<void> _pickTargetTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _targetTime,
    );
    if (mounted && picked != null) setState(() => _targetTime = picked);
  }

  Future<void> _onYes() async {
    if (_starting) return;
    setState(() => _starting = true);
    final wakeTime = DateTime.now();
    // The day mode compares the real wake-up with the user's target wake time.
    var targetWakeMinutes = DayModeCalculator.defaultTargetMinutes;
    try {
      final settings = await DatabaseService.instance.getSettings();
      targetWakeMinutes =
          settings.wakeReminderHour * 60 + settings.wakeReminderMinute;
    } catch (_) {
      // Fall back to the default rather than blocking the start of the day.
    }
    if (!mounted) return;
    final mode = DayModeCalculator.calculate(
      wakeTime,
      targetMinutes: targetWakeMinutes,
    );
    unawaited(_saveTarget());
    final target = _target;

    final generated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DayModeScreen(dayMode: mode, wakeTime: wakeTime, target: target),
      ),
    );
    if (!mounted) return;
    setState(() => _starting = false);
    // The routine was generated: pass that on so Home opens Today directly.
    if (generated == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final greeting = greetingFor(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('WakeFlow')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${greeting.text} ${greeting.emoji}',
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(height: 8),
              Text(
                'Ready to start your day?',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              // Target mode: how today's usable time gets bounded. The last
              // choice is remembered and prefilled.
              SegmentedButton<RoutineTargetMode>(
                segments: const [
                  ButtonSegment(
                    value: RoutineTargetMode.targetTime,
                    label: Text('Target Time'),
                    icon: Icon(Icons.schedule),
                  ),
                  ButtonSegment(
                    value: RoutineTargetMode.targetDuration,
                    label: Text('Target Duration'),
                    icon: Icon(Icons.timer_outlined),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) =>
                    setState(() => _mode = selection.first),
              ),
              const SizedBox(height: 16),
              if (_mode == RoutineTargetMode.targetTime)
                OutlinedButton.icon(
                  onPressed: _pickTargetTime,
                  icon: const Icon(Icons.access_time),
                  label: Text('Finish by ${_targetTime.format(context)}'),
                )
              else
                Column(
                  children: [
                    Text(
                      '${(_targetDurationMinutes / 60).toStringAsFixed(1)} hours',
                      style: const TextStyle(fontSize: 16),
                    ),
                    Slider(
                      value: _targetDurationMinutes.toDouble(),
                      min: 60,
                      max: 16 * 60,
                      divisions: (16 * 60 - 60) ~/ 30, // 30-minute steps
                      label:
                          '${(_targetDurationMinutes / 60).toStringAsFixed(1)}h',
                      onChanged: (value) => setState(
                        () => _targetDurationMinutes = value.round(),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _starting ? null : _onYes,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                ),
                child: const Text('YES, START', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
