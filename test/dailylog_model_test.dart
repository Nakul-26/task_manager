import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/models.dart';

void main() {
  test('DailyLog model should convert to and from Map', () {
    final log = DailyLog(
      date: '2026-01-24',
      habitId: 'habit-1',
      completed: true,
      count: 5,
      quality: 3,
      type: HabitType.counted,
      frequency: Frequency.weekly,
      daysOfWeek: [1, 3, 5],
      timesPerDay: 5,
    );

    final map = log.toMap();
    final newLog = DailyLog.fromMap(map);

    expect(newLog.date, '2026-01-24');
    expect(newLog.habitId, 'habit-1');
    expect(newLog.completed, true);
    expect(newLog.count, 5);
    expect(newLog.quality, 3);
    expect(newLog.type, HabitType.counted);
    expect(newLog.frequency, Frequency.weekly);
    expect(newLog.daysOfWeek, [1, 3, 5]);
    expect(newLog.timesPerDay, 5);
  });
}
