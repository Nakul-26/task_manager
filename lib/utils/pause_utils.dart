import 'package:hive/hive.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/utils/habit_schedule_utils.dart' as schedule_utils;

const String appSettingsBoxName = 'appSettings';
const String pausePeriodsKey = 'pausePeriods';

List<PausePeriod> loadPausePeriods(Box<dynamic> settingsBox) {
  final raw = settingsBox.get(pausePeriodsKey, defaultValue: <dynamic>[]);
  if (raw is! List) {
    return <PausePeriod>[];
  }
  return raw
      .whereType()
      .map((entry) => PausePeriod.fromMap(Map<String, dynamic>.from(entry)))
      .toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
}

Future<void> savePausePeriods(
  Box<dynamic> settingsBox,
  List<PausePeriod> pausePeriods,
) {
  final serialized = pausePeriods.map((period) => period.toMap()).toList();
  return settingsBox.put(pausePeriodsKey, serialized);
}

bool isPausedOnDate(List<PausePeriod> pausePeriods, DateTime date) {
  final normalizedDate = schedule_utils.normalizeDate(date);
  return pausePeriods.any((period) {
    final normalizedStart = schedule_utils.normalizeDate(period.startDate);
    final normalizedEnd = schedule_utils.normalizeDate(period.endDate);
    return !normalizedDate.isBefore(normalizedStart) &&
        !normalizedDate.isAfter(normalizedEnd);
  });
}

PausePeriod? getActivePausePeriod(
  List<PausePeriod> pausePeriods, {
  DateTime? today,
}) {
  final normalizedToday = schedule_utils.normalizeDate(today ?? DateTime.now());
  for (final period in pausePeriods) {
    if (isPausedOnDate([period], normalizedToday)) {
      return period;
    }
  }
  return null;
}
