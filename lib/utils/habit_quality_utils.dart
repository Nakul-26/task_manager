import 'package:flutter/material.dart';
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

String qualityScoreLabel(double? score) {
  if (score == null) {
    return 'Unrated';
  }
  if (score < 1.5) {
    return 'Poor';
  }
  if (score < 2.5) {
    return 'Average';
  }
  if (score < 3.5) {
    return 'Good';
  }
  return 'Excellent';
}

String qualityScoreStars(double? score) {
  if (score == null) {
    return '☆☆☆☆';
  }
  if (score < 1.5) {
    return '⭐☆☆☆';
  }
  if (score < 2.5) {
    return '⭐⭐☆☆';
  }
  if (score < 3.5) {
    return '⭐⭐⭐☆';
  }
  return '⭐⭐⭐⭐';
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

Color qualityTrendColor(HabitQualityTrend trend) {
  switch (trend) {
    case HabitQualityTrend.improving:
      return Colors.green;
    case HabitQualityTrend.stable:
      return Colors.blue;
    case HabitQualityTrend.declining:
      return Colors.orange;
    case HabitQualityTrend.insufficientData:
      return Colors.grey;
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
  double threshold = 0.3,
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

HabitQualityTrend calculateQualityTrendFromRatedLogs(
  Iterable<DailyLog> logs, {
  double threshold = 0.3,
  int windowSize = 7,
}) {
  final ratedLogs = logs
      .where((log) => log.completed && log.quality != null && log.quality! > 0)
      .toList();
  if (ratedLogs.length < 2) {
    return HabitQualityTrend.insufficientData;
  }

  // Take recent window and previous window from chronological logs
  final total = ratedLogs.length;
  final recentCount = total > windowSize ? windowSize : (total ~/ 2);
  if (recentCount == 0) {
    return HabitQualityTrend.insufficientData;
  }
  final recentLogs = ratedLogs.sublist(total - recentCount);
  final remainingLogs = ratedLogs.sublist(0, total - recentCount);
  final previousCount = remainingLogs.length > windowSize
      ? windowSize
      : remainingLogs.length;
  if (previousCount == 0) {
    return HabitQualityTrend.insufficientData;
  }
  final previousLogs = remainingLogs.sublist(remainingLogs.length - previousCount);

  return calculateQualityTrend(
    recentLogs: recentLogs,
    previousLogs: previousLogs,
    threshold: threshold,
  );
}

