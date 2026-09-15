import 'package:flutter/material.dart';
import '../services/day_mode_calculator.dart';
import 'day_mode_screen.dart';

class WakeScreen extends StatelessWidget {
  const WakeScreen({super.key});

  void _onYes(BuildContext context) {
    final wakeTime = DateTime.now();
    final mode = DayModeCalculator.calculate(wakeTime);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DayModeScreen(dayMode: mode, wakeTime: wakeTime),
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
              const SizedBox(height: 40),
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