import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WakeFlow')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Good morning 👋',
              style: TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                // Wake Check flow comes in Phase 2 — placeholder for now
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Start Day pressed')),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              child: const Text('Start Day', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}