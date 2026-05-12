import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/manage_habits_screen.dart';
import 'package:habit_tracker/models.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  const habitsBoxName = 'habits_manage_test';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('manage_habits_');
    Hive.init(tempDir.path);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getDownloadsDirectory' ||
            methodCall.method == 'getApplicationDocumentsDirectory' ||
            methodCall.method == 'getTemporaryDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );

    HiveBoxNames.habits = habitsBoxName;
    await Hive.openBox(habitsBoxName);
  });

  setUp(() async {
    await Hive.box(habitsBoxName).clear();
  });

  tearDownAll(() async {
    HiveBoxNames.habits = 'habits';
    await Hive.close();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('exports a JSON backup file instead of copying text', (
    tester,
  ) async {
    final habit = Habit(
      id: 'habit-1',
      name: 'Read',
      description: 'Daily reading',
      reminderEnabled: false,
      timerMinutes: null,
      createdAt: DateTime(2026, 5, 12, 10, 30),
    );
    await Hive.box(habitsBoxName).put(habit.id, habit.toMap());

    await tester.pumpWidget(
      const MaterialApp(home: ManageHabitsScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export Backup'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Export File'));
    await tester.pumpAndSettle();

    final exportFiles = tempDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList();

    expect(exportFiles, hasLength(1));

    final exportedJson = jsonDecode(await exportFiles.single.readAsString())
        as Map<String, dynamic>;

    expect(exportedJson['appVersion'], 1);
    expect(exportedJson['habitCount'], 1);

    final exportedHabit =
        (exportedJson['habits'] as List<dynamic>).single as Map<String, dynamic>;
    expect(exportedHabit['id'], 'habit-1');
    expect(exportedHabit['name'], 'Read');
    expect(exportedHabit['description'], 'Daily reading');
    expect(exportedHabit.containsKey('timerMinutes'), isFalse);
    expect(exportedHabit.containsKey('reminderEnabled'), isFalse);
    expect(exportedHabit.containsKey('color'), isFalse);
  });
}
