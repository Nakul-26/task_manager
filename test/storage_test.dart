import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hive/hive.dart';
import 'package:habit_tracker/models.dart';

// Create a mock class for the Box
class MockBox extends Mock implements Box {}

void main() {
  late MockBox mockHabitsBox;

  setUp(() {
    mockHabitsBox = MockBox();
  });

  test('Habit is added to storage', () {
    // Arrange
    final habit = Habit(
      id: '1',
      name: 'Test Habit',
      description: 'A habit for testing',
      createdAt: DateTime.now(),
    );
    
    // Stub the 'put' method to do nothing, as we are just verifying the call.
    when(() => mockHabitsBox.put(any(), any())).thenAnswer((_) async => Future.value());

    // Act
    mockHabitsBox.put(habit.id, habit.toMap());

    // Assert
    // Verify that put was called exactly once with the correct arguments.
    verify(() => mockHabitsBox.put(habit.id, habit.toMap())).called(1);
  });

  test('Habit is read from storage', () {
    // Arrange
    final habitMap = {
      'id': '1',
      'name': 'Test Habit',
      'description': 'A habit for testing',
      'isImportant': false,
      'type': HabitType.binary.index,
      'frequency': Frequency.daily.index,
      'color': 4280391411, // Colors.blue.value
      'createdAt': DateTime(2026, 1, 24).toIso8601String(),
    };
    when(() => mockHabitsBox.get('1')).thenReturn(habitMap);

    // Act
    final result = mockHabitsBox.get('1') as Map<dynamic, dynamic>;
    final habit = Habit.fromMap(Map<String, dynamic>.from(result));

    // Assert
    expect(habit.name, 'Test Habit');
    expect(habit.id, '1');
  });
}
