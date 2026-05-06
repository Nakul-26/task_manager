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
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (MethodCall methodCall) async => 'UTC',
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (MethodCall methodCall) async => null,
    );
  });

  setUp(() async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    habitsBoxName = 'habits_$suffix';
    HiveBoxNames.habits = habitsBoxName;
    await Hive.openBox(habitsBoxName);
  });

  tearDown(() async {
    if (Hive.isBoxOpen(habitsBoxName)) {
      await Hive.box(habitsBoxName).close();
    }
    await Hive.deleteBoxFromDisk(habitsBoxName);
  });

  tearDownAll(() async {
    HiveBoxNames.habits = 'habits';
    await Hive.close();
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Ignore deletion errors in tests if files are still locked
      }
    }
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      null,
    );
  });

  testWidgets(
    'Saving uses entered name and description text',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      await tester.pumpWidget(
        MaterialApp(home: AddEditHabitScreen(onHabitSaved: (_) async {})),
      );
      await tester.pump();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Deep Work');
      await tester.enterText(fields.at(1), 'Focus block');

      final saveButton = find.widgetWithText(ElevatedButton, 'Save');
      await tester.tap(saveButton);
      // Wait for the save operation and navigation pop
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(); // Try settle again, but after explicit pumps

      final storedHabit = Habit.fromMap(
        Map<String, dynamic>.from(Hive.box(HiveBoxNames.habits).values.single),
      );
      expect(storedHabit.name, 'Deep Work');
      expect(storedHabit.description, 'Focus block');
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
