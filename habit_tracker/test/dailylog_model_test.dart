import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/models.dart';

void main() {
  test('DailyLog model should convert to and from Map', () {
    final log = DailyLog(
      date: '2026-01-24',
      habitId: 'habit-1',
      completed: true,
      count: 5,
    );

    final map = log.toMap();
    final newLog = DailyLog.fromMap(map);

    expect(newLog.date, '2026-01-24');
    expect(newLog.habitId, 'habit-1');
    expect(newLog.completed, true);
    expect(newLog.count, 5);
  });
}
