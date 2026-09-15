import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const WakeFlowApp());
}

class WakeFlowApp extends StatelessWidget {
  const WakeFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WakeFlow',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}