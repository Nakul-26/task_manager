import 'package:habit_tracker/models.dart';

enum HabitQualityTrend { improving, stable, declining, insufficientData }

String qualityLabel(int quality) {
  switch (quality) {
    case 1:
      return 'Poor';
    case 2:
      return 'Average';
    case 3:
      return 'Good';
    case 4:
      return 'Excellent';
    default:
      return 'Unrated';
  }
}

String qualityTrendLabel(HabitQualityTrend trend) {
  switch (trend) {
    case HabitQualityTrend.improving:
      return 'Improving';
    case HabitQualityTrend.stable:
      return 'Stable';
    case HabitQualityTrend.declining:
      return 'Needs improvement';
    case HabitQualityTrend.insufficientData:
      return 'Build more data';
  }
}

double? averageQuality(Iterable<DailyLog> logs) {
  final ratedLogs = logs.where(
    (log) => log.completed && log.quality != null && log.quality! > 0,
  );
  final total = ratedLogs.fold<int>(0, (sum, log) => sum + log.quality!);
  final count = ratedLogs.length;
  if (count == 0) {
    return null;
  }
  return total / count;
}

HabitQualityTrend calculateQualityTrend({
  required List<DailyLog> recentLogs,
  required List<DailyLog> previousLogs,
  double threshold = 0.1,
}) {
  final recentAverage = averageQuality(recentLogs);
  final previousAverage = averageQuality(previousLogs);
  if (recentAverage == null || previousAverage == null) {
    return HabitQualityTrend.insufficientData;
  }
  final delta = recentAverage - previousAverage;
  if (delta > threshold) {
    return HabitQualityTrend.improving;
  }
  if (delta < -threshold) {
    return HabitQualityTrend.declining;
  }
  return HabitQualityTrend.stable;
}
