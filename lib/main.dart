import 'package:habit_tracker/box_names.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/today_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  await Future.wait([
    Hive.openBox(HiveBoxNames.habits),
    Hive.openBox(HiveBoxNames.dailyLogs),
    Hive.openBox(HiveBoxNames.appSettings),
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Habit Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const TodayScreen(),
    );
  }
}
