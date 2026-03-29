import 'package:flutter/material.dart';
import 'package:habit_tracker/models.dart';

bool isHabitVisibleAt(Habit habit, TimeOfDay currentTime) {
  if (!habit.useTimeVisibility ||
      habit.visibleAfterHour == null ||
      habit.visibleAfterMinute == null) {
    return true;
  }

  final currentMinutes = (currentTime.hour * 60) + currentTime.minute;
  final visibleAfterMinutes =
      (habit.visibleAfterHour! * 60) + habit.visibleAfterMinute!;
  return currentMinutes >= visibleAfterMinutes;
}

bool isHabitVisibleNow(Habit habit, {DateTime? now}) {
  final current = now ?? DateTime.now();
  return isHabitVisibleAt(
    habit,
    TimeOfDay(hour: current.hour, minute: current.minute),
  );
}

String? formatHabitVisibleAfter(Habit habit, BuildContext context) {
  if (!habit.useTimeVisibility ||
      habit.visibleAfterHour == null ||
      habit.visibleAfterMinute == null) {
    return null;
  }

  final time = TimeOfDay(
    hour: habit.visibleAfterHour!,
    minute: habit.visibleAfterMinute!,
  );
  return time.format(context);
}
