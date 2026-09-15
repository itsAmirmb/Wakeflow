import 'package:flutter/material.dart';
import '../models/day_mode.dart';

class DayModeScreen extends StatelessWidget {
  final DayMode dayMode;
  final DateTime wakeTime;

  const DayModeScreen({
    super.key,
    required this.dayMode,
    required this.wakeTime,
  });

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
              Text(
                '${dayMode.label} DAY',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'Woke up at ${wakeTime.hour}:${wakeTime.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              const Text(
                'Routine generation coming in the next phase.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}