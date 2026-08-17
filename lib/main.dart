import 'package:habit_tracker/box_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:habit_tracker/home_shell.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  await Future.wait([
    Hive.openBox(HiveBoxNames.habits),
    Hive.openBox(HiveBoxNames.dailyLogs),
    Hive.openBox(HiveBoxNames.appSettings),
    Hive.openBox(HiveBoxNames.oneTimeTasks),
    Hive.openBox(HiveBoxNames.reminders),
    Hive.openBox(HiveBoxNames.notes),
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Habit Tracker',
      scrollBehavior: AppScrollBehavior(),
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomeShell(),
    );
  }
}
