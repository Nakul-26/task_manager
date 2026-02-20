import 'package:habit_tracker/models.dart';

DateTime normalizeDate(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

String formatDate(DateTime date) {
  final normalized = normalizeDate(date);
  return '${normalized.year}-${normalized.month.toString().padLeft(2, '0')}-${normalized.day.toString().padLeft(2, '0')}';
}

bool isSameDate(DateTime a, DateTime b) {
  final normalizedA = normalizeDate(a);
  final normalizedB = normalizeDate(b);
  return normalizedA.year == normalizedB.year &&
      normalizedA.month == normalizedB.month &&
      normalizedA.day == normalizedB.day;
}

bool isScheduledDay(Habit habit, DateTime date) {
  final normalized = normalizeDate(date);
  switch (habit.frequency) {
    case Frequency.daily:
      return true;
    case Frequency.weekly:
      return habit.daysOfWeek?.contains(normalized.weekday) ?? false;
    case Frequency.oddDays:
      return normalized.day.isOdd;
    case Frequency.evenDays:
      return normalized.day.isEven;
  }
}
