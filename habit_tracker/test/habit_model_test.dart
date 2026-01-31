import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Habit model should convert to and from Map', () {
    final habit = Habit(
      id: '1',
      name: 'Read',
      isImportant: true,
      description: 'Read a book for 30 minutes',
      createdAt: DateTime(2026, 1, 1),
    );

    final map = habit.toMap();
    final newHabit = Habit.fromMap(map);

    expect(newHabit.id, '1');
    expect(newHabit.name, 'Read');
    expect(newHabit.isImportant, true);
    expect(newHabit.description, 'Read a book for 30 minutes');
    expect(newHabit.createdAt, DateTime(2026, 1, 1));
  });
}
