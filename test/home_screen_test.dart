import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/utils/pause_utils.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHome(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(const MyApp());
    await tester.pump();
  }

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp();

    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );

    Hive.init(tempDir.path);
    await Hive.openBox('habits');
    await Hive.openBox('dailyLogs');
    await Hive.openBox(appSettingsBoxName);
  });

  // Clear boxes before each test
  setUp(() async {
    await Hive.box('habits').clear();
    await Hive.box('dailyLogs').clear();
    await Hive.box(appSettingsBoxName).clear();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('Home screen shows app bar title', (WidgetTester tester) async {
    await pumpHome(tester);

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

    await pumpHome(tester);

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

    await pumpHome(tester);

    // Verify checkbox is initially unchecked
    Checkbox checkbox = tester.widget(find.byType(Checkbox));
    expect(checkbox.value, false);

    // Tap the checkbox
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    // Verify checkbox is now checked
    checkbox = tester.widget(find.byType(Checkbox));
    expect(checkbox.value, true);
  });

  testWidgets('Archived habits are hidden from today list', (
    WidgetTester tester,
  ) async {
    final archivedHabit = Habit(
      id: '2',
      name: 'Archived Habit',
      description: 'Should not show in today list',
      isArchived: true,
      createdAt: DateTime.now(),
      archivedAt: DateTime.now(),
    );
    await Hive.box('habits').put(archivedHabit.id, archivedHabit.toMap());

    await pumpHome(tester);

    expect(find.text('Archived Habit'), findsNothing);
  });

  testWidgets('Habits stay hidden until their visible-after time', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final hiddenUntil = now.hour == 23 && now.minute == 59
        ? const TimeOfDay(hour: 23, minute: 59)
        : TimeOfDay(
            hour: now.minute == 59 ? now.hour + 1 : now.hour,
            minute: now.minute == 59 ? 0 : now.minute + 1,
          );
    final habit = Habit(
      id: 'timed-hidden',
      name: 'Evening Study',
      description: 'Should appear later',
      useTimeVisibility: true,
      visibleAfterHour: hiddenUntil.hour,
      visibleAfterMinute: hiddenUntil.minute,
      createdAt: now,
    );
    await Hive.box('habits').put(habit.id, habit.toMap());

    await pumpHome(tester);

    expect(find.text('Evening Study'), findsNothing);
  });

  testWidgets('Paused today shows banner and disables completion', (
    WidgetTester tester,
  ) async {
    final today = DateTime.now();
    final habit = Habit(
      id: '3',
      name: 'Paused Habit',
      description: 'Should be disabled while paused',
      createdAt: today,
    );
    await Hive.box('habits').put(habit.id, habit.toMap());
    await Hive.box(appSettingsBoxName).put(pausePeriodsKey, [
      PausePeriod(startDate: today, endDate: today).toMap(),
    ]);

    await pumpHome(tester);

    expect(find.textContaining('Tracking paused until'), findsOneWidget);

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.onChanged, isNull);
    expect(find.text('Tracking paused today'), findsOneWidget);
  });
}
