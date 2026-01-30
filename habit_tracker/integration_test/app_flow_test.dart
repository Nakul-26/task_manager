import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:habit_tracker/main.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    
    // In a real app, you would mock the path provider.
    // For this integration test, we let it use the real implementation,
    // which will create a file in the test environment.
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

  testWidgets('Add habit flow', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Open add screen
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Enter habit name
    await tester.enterText(find.byType(TextFormField).first, 'Coding');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verify habit appears on the home screen
    expect(find.text('Coding'), findsOneWidget);
  });
}
