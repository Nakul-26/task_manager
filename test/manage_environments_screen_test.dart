import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/manage_environments_screen.dart';
import 'package:habit_tracker/utils/execution_environment_utils.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  const appSettingsBoxName = 'appSettings_test';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_env_test_');
    Hive.init(tempDir.path);
    HiveBoxNames.appSettings = appSettingsBoxName;
    await Hive.openBox(appSettingsBoxName);
  });

  setUp(() async {
    await Hive.box(appSettingsBoxName).clear();
  });

  tearDownAll(() async {
    HiveBoxNames.appSettings = 'appSettings';
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Built-in environment titles stay single-line', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ManageEnvironmentsScreen()),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Deep Work'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);

    final subtitle = tester.widget<Text>(find.text('Requires uninterrupted focus.'));
    expect(subtitle.maxLines, 1);
    expect(subtitle.overflow, TextOverflow.ellipsis);

    expect(find.text('Built-in'), findsNWidgets(3));
  });

  testWidgets('Reset defaults asks for confirmation before restoring built-ins', (
    WidgetTester tester,
  ) async {
    await saveExecutionEnvironments(
      Hive.box(appSettingsBoxName),
      const [
        ExecutionEnvironment(
          id: 'lab',
          name: 'Lab',
          description: 'Custom environment',
          color: Colors.green,
          iconKey: 'work',
          sortOrder: 0,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: ManageEnvironmentsScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lab'), findsOneWidget);
    expect(find.text('Deep Work'), findsNothing);

    await tester.tap(find.byTooltip('Reset defaults'));
    await tester.pumpAndSettle();

    expect(find.text('Reset defaults'), findsOneWidget);
    expect(
      find.text('Are you sure you want to restore the built-in environments?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Lab'), findsOneWidget);

    await tester.tap(find.byTooltip('Reset defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Lab'), findsNothing);
    expect(find.text('Deep Work'), findsOneWidget);
    expect(find.text('College'), findsOneWidget);
    expect(find.text('Quick Task'), findsOneWidget);
  });
}
