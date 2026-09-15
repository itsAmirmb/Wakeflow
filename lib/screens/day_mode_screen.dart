import 'package:flutter/material.dart';
import '../models/day_mode.dart';
import '../data/default_categories.dart';
import '../widgets/category_card.dart';

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Text(
                  '${dayMode.label} DAY',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Woke up at ${wakeTime.hour}:${wakeTime.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              children: defaultCategories
                  .map((category) => CategoryCard(category: category))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}