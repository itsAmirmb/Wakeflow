import 'package:flutter/material.dart';
import '../models/routine_target.dart';
import '../services/day_mode_calculator.dart';
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

  RoutineTarget get _target {
    return _mode == RoutineTargetMode.targetTime
        ? RoutineTarget.time(hour: _targetTime.hour, minute: _targetTime.minute)
        : RoutineTarget.duration(minutes: _targetDurationMinutes);
  }

  Future<void> _pickTargetTime() async {
    final picked = await showTimePicker(context: context, initialTime: _targetTime);
    if (picked != null) setState(() => _targetTime = picked);
  }

  void _onYes(BuildContext context) {
    final wakeTime = DateTime.now();
    final mode = DayModeCalculator.calculate(wakeTime);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DayModeScreen(
          dayMode: mode,
          wakeTime: wakeTime,
          target: _target,
        ),
      ),
    );
  }

  void _onLater(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reminder set for 30 minutes later')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WakeFlow')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('بیدار شدی؟', style: TextStyle(fontSize: 28)),
              const SizedBox(height: 32),
              // Target mode: how today's usable time gets bounded.
              // Chosen fresh each morning, not a fixed setting.
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
                      label: '${(_targetDurationMinutes / 60).toStringAsFixed(1)}h',
                      onChanged: (value) =>
                          setState(() => _targetDurationMinutes = value.round()),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _onYes(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                ),
                child: const Text('YES, START', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _onLater(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                ),
                child: const Text('30 MIN LATER', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}