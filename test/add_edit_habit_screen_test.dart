import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/add_edit_habit_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('add_edit_env_test_');
    Hive.init(tempDir.path);
    HiveBoxNames.appSettings = 'add_edit_env_settings_test';
    await Hive.openBox(HiveBoxNames.appSettings);
  });

  tearDownAll(() async {
    HiveBoxNames.appSettings = 'appSettings';
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Add/edit screen shows execution context control', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AddEditHabitScreen()),
    );
    await tester.pump();

    expect(find.byType(DropdownButtonFormField<String>), findsAtLeastNWidgets(1));
    expect(find.text('Execution Environment'), findsOneWidget);
  });
}
