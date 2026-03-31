import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/utils/pause_utils.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  const habitsBoxName = 'habits_test';
  const dailyLogsBoxName = 'dailyLogs_test';
  const appSettingsBoxName = 'appSettings_test';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
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

    HiveBoxNames.habits = habitsBoxName;
    HiveBoxNames.dailyLogs = dailyLogsBoxName;
    HiveBoxNames.appSettings = appSettingsBoxName;

    await Hive.openBox(habitsBoxName);
    await Hive.openBox(dailyLogsBoxName);
    await Hive.openBox(appSettingsBoxName);
  });

  setUp(() async {
    await Hive.box(habitsBoxName).clear();
    await Hive.box(dailyLogsBoxName).clear();
    await Hive.box(appSettingsBoxName).clear();
  });

  tearDown(() async {
    await Hive.box(habitsBoxName).clear();
    await Hive.box(dailyLogsBoxName).clear();
    await Hive.box(appSettingsBoxName).clear();
  });

  tearDownAll(() async {
    HiveBoxNames.habits = 'habits';
    HiveBoxNames.dailyLogs = 'dailyLogs';
    HiveBoxNames.appSettings = 'appSettings';
    await Hive.close();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  Future<void> pumpHome(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(const MyApp());
    await tester.pump();
  }

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
    await Hive.box(HiveBoxNames.habits).put(habit.id, habit.toMap());

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
    await Hive.box(HiveBoxNames.habits).put(habit.id, habit.toMap());

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
    expect(find.text('Test Habit'), findsOneWidget);
    expect(find.textContaining('Completed ('), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Completed (1)'), findsOneWidget);
    expect(find.text('Test Habit'), findsNothing);
  });

  testWidgets('Unchecking before delay keeps habit active', (
    WidgetTester tester,
  ) async {
    final habit = Habit(
      id: 'delay-cancel',
      name: 'Delay Cancel Habit',
      description: 'Should stay active if unchecked quickly',
      createdAt: DateTime.now(),
    );
    await Hive.box(HiveBoxNames.habits).put(habit.id, habit.toMap());

    await pumpHome(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, false);
    expect(find.text('Delay Cancel Habit'), findsOneWidget);
    expect(find.textContaining('Completed ('), findsNothing);
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
    await Hive.box(
      HiveBoxNames.habits,
    ).put(archivedHabit.id, archivedHabit.toMap());

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
    await Hive.box(HiveBoxNames.habits).put(habit.id, habit.toMap());

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
    await Hive.box(HiveBoxNames.habits).put(habit.id, habit.toMap());
    await Hive.box(HiveBoxNames.appSettings).put(pausePeriodsKey, [
      PausePeriod(startDate: today, endDate: today).toMap(),
    ]);

    await pumpHome(tester);

    expect(find.textContaining('Tracking paused until'), findsOneWidget);

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.onChanged, isNull);
    expect(find.text('Tracking paused today'), findsOneWidget);
  });

  testWidgets('Completed habits are collapsed by default', (
    WidgetTester tester,
  ) async {
    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final activeHabit = Habit(
      id: 'active-1',
      name: 'Exercise',
      description: 'Still pending',
      createdAt: today,
    );
    final completedHabit = Habit(
      id: 'done-1',
      name: 'Brush Teeth',
      description: 'Already done',
      createdAt: today,
    );

    await Hive.box(
      HiveBoxNames.habits,
    ).put(activeHabit.id, activeHabit.toMap());
    await Hive.box(
      HiveBoxNames.habits,
    ).put(completedHabit.id, completedHabit.toMap());
    await Hive.box(HiveBoxNames.dailyLogs).put('${completedHabit.id}_$todayKey', {
      'date': todayKey,
      'habitId': completedHabit.id,
      'completed': true,
      'count': null,
    });

    await pumpHome(tester);

    expect(find.text('Exercise'), findsOneWidget);
    expect(find.text('Completed (1)'), findsOneWidget);
    expect(find.text('Brush Teeth'), findsNothing);
  });

  testWidgets('Completed habits expand when tapping completed header', (
    WidgetTester tester,
  ) async {
    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final completedHabit = Habit(
      id: 'done-2',
      name: 'Morning Walk',
      description: 'Already done',
      createdAt: today,
    );

    await Hive.box(
      HiveBoxNames.habits,
    ).put(completedHabit.id, completedHabit.toMap());
    await Hive.box(HiveBoxNames.dailyLogs).put('${completedHabit.id}_$todayKey', {
      'date': todayKey,
      'habitId': completedHabit.id,
      'completed': true,
      'count': null,
    });

    await pumpHome(tester);

    expect(find.text('Morning Walk'), findsNothing);

    await tester.tap(find.text('Completed (1)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Morning Walk'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 15)));
}
