import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/utils/habit_schedule_utils.dart'
    as schedule_utils;
import 'package:habit_tracker/utils/habit_visibility_utils.dart';

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
      executionContext: ExecutionContext.deepWork,
      useTimeVisibility: true,
      visibleAfterHour: 18,
      visibleAfterMinute: 30,
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
    expect(newHabit.executionContext, ExecutionContext.deepWork);
    expect(newHabit.useTimeVisibility, true);
    expect(newHabit.visibleAfterHour, 18);
    expect(newHabit.visibleAfterMinute, 30);
    expect(newHabit.createdAt, DateTime(2026, 1, 1));
    expect(newHabit.archivedAt, DateTime(2026, 2, 1));
    expect(newHabit.ruleHistory, isNotEmpty);
  });

  test(
    'Habit model should derive importance score from legacy isImportant',
    () {
      final legacyMap = {
        'id': 'legacy-1',
        'name': 'Legacy habit',
        'isImportant': true,
        'isArchived': false,
        'description': '',
        'type': HabitType.binary.index,
        'frequency': Frequency.daily.index,
        'executionContext': ExecutionContext.quickTask.index,
        'color': 0xFF2196F3,
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };

      final habit = Habit.fromMap(legacyMap);

      expect(habit.isImportant, true);
      expect(habit.importanceScore, 1);
      expect(habit.executionContext, ExecutionContext.quickTask);
      expect(habit.useTimeVisibility, false);
      expect(habit.visibleAfterHour, isNull);
      expect(habit.visibleAfterMinute, isNull);
    },
  );

  test('Time-based visibility compares against visible after time', () {
    final habit = Habit(
      id: 'timed-1',
      name: 'Study',
      description: 'Evening study block',
      useTimeVisibility: true,
      visibleAfterHour: 18,
      visibleAfterMinute: 0,
      createdAt: DateTime(2026, 1, 1),
    );

    expect(
      isHabitVisibleAt(habit, const TimeOfDay(hour: 17, minute: 59)),
      false,
    );
    expect(isHabitVisibleAt(habit, const TimeOfDay(hour: 18, minute: 0)), true);
  });

  test('PausePeriod should convert to and from Map', () {
    final period = PausePeriod(
      startDate: DateTime(2026, 3, 24, 9, 30),
      endDate: DateTime(2026, 3, 29, 18, 0),
      description: 'Exam prep',
    );

    final map = period.toMap();
    final newPeriod = PausePeriod.fromMap(map);

    expect(newPeriod.startDate, DateTime(2026, 3, 24));
    expect(newPeriod.endDate, DateTime(2026, 3, 29));
    expect(newPeriod.description, 'Exam prep');
  });

  test('Habit schedule uses the rule active on a date', () {
    final habit = Habit(
      id: 'history-1',
      name: 'Study',
      description: 'Study block',
      createdAt: DateTime(2026, 1, 1),
      startDate: DateTime(2026, 1, 1),
      ruleHistory: [
        HabitRuleSnapshot(
          effectiveFrom: DateTime(2026, 1, 1),
          type: HabitType.binary,
          frequency: Frequency.daily,
        ),
        HabitRuleSnapshot(
          effectiveFrom: DateTime(2026, 1, 10),
          type: HabitType.binary,
          frequency: Frequency.weekly,
          daysOfWeek: [1, 3],
        ),
      ],
    );

    expect(schedule_utils.isScheduledDay(habit, DateTime(2026, 1, 8)), true);
    expect(schedule_utils.isScheduledDay(habit, DateTime(2026, 1, 12)), true);
    expect(schedule_utils.isScheduledDay(habit, DateTime(2026, 1, 13)), false);
  });

  test('Habit export includes non-default execution context', () {
    final habit = Habit(
      id: 'export-1',
      name: 'Study',
      description: 'Deep work block',
      executionContext: ExecutionContext.deepWork,
      createdAt: DateTime(2026, 1, 1),
    );

    final exported = habit.toExportMap();

    expect(exported['executionContext'], ExecutionContext.deepWork.index);
  });
}
