import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/add_edit_habit_screen.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late String habitsBoxName;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_add_edit_');
    Hive.init(tempDir.path);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(
        'dexterous.com/flutter/local_notifications',
      ),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  setUp(() async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    habitsBoxName = 'habits_$suffix';
    HiveBoxNames.habits = habitsBoxName;
    await Hive.openBox(habitsBoxName);
  });

  tearDown(() async {
    await Hive.box(habitsBoxName).close();
    await Hive.deleteBoxFromDisk(habitsBoxName);
  });

  tearDownAll(() async {
    HiveBoxNames.habits = 'habits';
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(
        'dexterous.com/flutter/local_notifications',
      ),
      null,
    );
  });

  testWidgets(
    'Saving uses entered name and description text',
    (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AddEditHabitScreen()),
    );
    await tester.pump();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Deep Work');
    await tester.enterText(fields.at(1), 'Focus block');

    final saveButton = find.widgetWithText(ElevatedButton, 'Save');
    await tester.scrollUntilVisible(
      saveButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final storedHabit = Habit.fromMap(
      Map<String, dynamic>.from(Hive.box(HiveBoxNames.habits).values.single),
    );
    expect(storedHabit.name, 'Deep Work');
    expect(storedHabit.description, 'Focus block');
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
