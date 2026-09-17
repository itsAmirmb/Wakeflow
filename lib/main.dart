import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';

void main() async {
  // Required before any plugin (sqflite, notifications) is used prior to runApp.
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();
  await NotificationService.instance.scheduleWakeReminder();

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