import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/utils/date_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Detects new day correctly', () {
    final yesterday = DateTime(2026, 1, 1);
    final today = DateTime(2026, 1, 2);

    expect(isNewDay(yesterday, today), true);
  });

  test('Detects same day correctly', () {
    final today1 = DateTime(2026, 1, 2, 10, 0, 0);
    final today2 = DateTime(2026, 1, 2, 14, 0, 0);

    expect(isNewDay(today1, today2), false);
  });
}
