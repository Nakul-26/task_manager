import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/models.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });

    Hive.init(tempDir.path);
    await Hive.openBox('habits');
    await Hive.openBox('dailyLogs');
  });

  // Clear boxes before each test
  setUp(() {
    Hive.box('habits').clear();
    Hive.box('dailyLogs').clear();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('Home screen shows app bar title', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Today\'s Habits'), findsOneWidget);
  });

  testWidgets('Habits list shows a habit', (WidgetTester tester) async {
    // Add a habit to the box
    final habit = Habit(
      id: '1',
      name: 'Test Habit',
      description: 'A habit for testing',
      createdAt: DateTime.now(),
    );
    await Hive.box('habits').put(habit.id, habit.toMap());

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Test Habit'), findsOneWidget);
  });

  testWidgets('Mark habit as completed', (WidgetTester tester) async {
    // Add a habit to the box
    final habit = Habit(
      id: '1',
      name: 'Test Habit',
      description: 'A habit for testing',
      createdAt: DateTime.now(),
    );
    await Hive.box('habits').put(habit.id, habit.toMap());
    
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Verify checkbox is initially unchecked
    Checkbox checkbox = tester.widget(find.byType(Checkbox));
    expect(checkbox.value, false);

    // Tap the checkbox
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Verify checkbox is now checked
    checkbox = tester.widget(find.byType(Checkbox));
    expect(checkbox.value, true);
  });
}

