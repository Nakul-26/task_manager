import 'package:hive/hive.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/utils/habit_schedule_utils.dart' as schedule_utils;

const String dailyTimeLimitMinutesKey = 'dailyTimeLimitMinutes';

int? loadDailyTimeLimitMinutes(Box<dynamic> settingsBox) {
  final raw = settingsBox.get(dailyTimeLimitMinutesKey);
  if (raw is int && raw > 0) {
    return raw;
  }
  return null;
}

Future<void> saveDailyTimeLimitMinutes(
  Box<dynamic> settingsBox,
  int? minutes,
) {
  if (minutes == null || minutes <= 0) {
    return settingsBox.delete(dailyTimeLimitMinutesKey);
  }
  return settingsBox.put(dailyTimeLimitMinutesKey, minutes);
}

bool isHabitActiveOnDate(Habit habit, DateTime date) {
  if (habit.isArchived) {
    return false;
  }
  final normalized = schedule_utils.normalizeDate(date);
  if (schedule_utils.normalizeDate(habit.startDate).isAfter(normalized)) {
    return false;
  }
  if (habit.endDate != null &&
      schedule_utils.normalizeDate(habit.endDate!).isBefore(normalized)) {
    return false;
  }
  return schedule_utils.isScheduledDay(habit, normalized);
}

List<Habit> habitsScheduledOnDate(List<Habit> habits, DateTime date) {
  return habits.where((habit) => isHabitActiveOnDate(habit, date)).toList();
}

int totalMinutesForDate(List<Habit> habits, DateTime date) {
  return habitsScheduledOnDate(habits, date)
      .fold<int>(0, (sum, habit) => sum + (habit.timerMinutes ?? 0));
}

String formatMinutesLabel(int minutes) {
  if (minutes <= 0) {
    return '0m';
  }
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (hours <= 0) {
    return '${remainingMinutes}m';
  }
  if (remainingMinutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${remainingMinutes}m';
}
