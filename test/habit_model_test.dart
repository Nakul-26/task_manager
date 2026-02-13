import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Habit model should convert to and from Map', () {
    final habit = Habit(
      id: '1',
      name: 'Read',
      isImportant: true,
      importanceScore: 4,
      isArchived: true,
      description: 'Read a book for 30 minutes',
      createdAt: DateTime(2026, 1, 1),
      archivedAt: DateTime(2026, 2, 1),
    );

    final map = habit.toMap();
    final newHabit = Habit.fromMap(map);

    expect(newHabit.id, '1');
    expect(newHabit.name, 'Read');
    expect(newHabit.isImportant, true);
    expect(newHabit.importanceScore, 4);
    expect(newHabit.isArchived, true);
    expect(newHabit.description, 'Read a book for 30 minutes');
    expect(newHabit.createdAt, DateTime(2026, 1, 1));
    expect(newHabit.archivedAt, DateTime(2026, 2, 1));
  });

  test('Habit model should derive importance score from legacy isImportant', () {
    final legacyMap = {
      'id': 'legacy-1',
      'name': 'Legacy habit',
      'isImportant': true,
      'isArchived': false,
      'description': '',
      'type': HabitType.binary.index,
      'frequency': Frequency.daily.index,
      'color': 0xFF2196F3,
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
    };

    final habit = Habit.fromMap(legacyMap);

    expect(habit.isImportant, true);
    expect(habit.importanceScore, 1);
  });
}
