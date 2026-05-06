import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/paused_sessions_screen.dart';
import 'package:habit_tracker/utils/pause_utils.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  const habitsBoxName = 'paused_sessions_habits_test';
  const dailyLogsBoxName = 'paused_sessions_daily_logs_test';
  const appSettingsBoxName = 'paused_sessions_settings_test';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('paused_sessions_test_');
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

  tearDownAll(() async {
    HiveBoxNames.habits = 'habits';
    HiveBoxNames.dailyLogs = 'dailyLogs';
    HiveBoxNames.appSettings = 'appSettings';
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PausedSessionsScreen(onPausePeriodsChanged: () async {}),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows saved paused sessions', (WidgetTester tester) async {
    await Hive.box(HiveBoxNames.appSettings).put(pausePeriodsKey, [
      PausePeriod(
        startDate: DateTime(2026, 4, 21),
        endDate: DateTime(2026, 4, 23),
        description: 'Tests',
      ).toMap(),
    ]);

    await pumpScreen(tester);

    expect(find.text('Paused Sessions'), findsOneWidget);
    expect(find.text('Apr 21, 2026 - Apr 23, 2026'), findsOneWidget);
    expect(find.text('3 days'), findsOneWidget);
    expect(find.text('Tests'), findsOneWidget);
  });

  testWidgets(
    'deletes a paused session',
    (WidgetTester tester) async {
      await Hive.box(HiveBoxNames.appSettings).put(pausePeriodsKey, [
        PausePeriod(
          startDate: DateTime(2026, 4, 21),
          endDate: DateTime(2026, 4, 23),
          description: 'Tests',
        ).toMap(),
      ]);

      await pumpScreen(tester);

      await tester.tap(find.byTooltip('Delete pause'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('No paused sessions'), findsOneWidget);
      expect(loadPausePeriods(Hive.box(HiveBoxNames.appSettings)), isEmpty);
    },
  );
}
