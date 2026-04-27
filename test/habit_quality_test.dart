import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/utils/habit_quality_utils.dart';

void main() {
  group('HabitQualityUtils', () {
    test('calculateQualityTrend returns insufficientData when one window is empty', () {
      final recentLogs = [
        DailyLog(date: '2026-04-27', habitId: '1', completed: true, quality: 3),
      ];
      final previousLogs = <DailyLog>[];

      expect(
        calculateQualityTrend(recentLogs: recentLogs, previousLogs: previousLogs),
        HabitQualityTrend.insufficientData,
      );
    });

    test('calculateQualityTrend returns improving when recent is better', () {
      final recentLogs = [
        DailyLog(date: '2026-04-27', habitId: '1', completed: true, quality: 4),
      ];
      final previousLogs = [
        DailyLog(date: '2026-04-20', habitId: '1', completed: true, quality: 3),
      ];

      expect(
        calculateQualityTrend(recentLogs: recentLogs, previousLogs: previousLogs),
        HabitQualityTrend.improving,
      );
    });

    test('calculateQualityTrend returns stable when difference is below threshold', () {
      final recentLogs = [
        DailyLog(date: '2026-04-27', habitId: '1', completed: true, quality: 3),
      ];
      final previousLogs = [
        DailyLog(date: '2026-04-20', habitId: '1', completed: true, quality: 3),
      ];

      expect(
        calculateQualityTrend(recentLogs: recentLogs, previousLogs: previousLogs),
        HabitQualityTrend.stable,
      );
    });

    test('calculateQualityTrend returns declining when recent is worse', () {
      final recentLogs = [
        DailyLog(date: '2026-04-27', habitId: '1', completed: true, quality: 2),
      ];
      final previousLogs = [
        DailyLog(date: '2026-04-20', habitId: '1', completed: true, quality: 3),
      ];

      expect(
        calculateQualityTrend(recentLogs: recentLogs, previousLogs: previousLogs),
        HabitQualityTrend.declining,
      );
    });
    
    test('averageQuality filters unrated logs', () {
      final logs = [
        DailyLog(date: '2026-04-27', habitId: '1', completed: true, quality: 4),
        DailyLog(date: '2026-04-26', habitId: '1', completed: true, quality: null),
        DailyLog(date: '2026-04-25', habitId: '1', completed: false, quality: 4),
      ];
      
      expect(averageQuality(logs), 4.0);
    });

    test('reproduce build more data with 8 days of data', () {
      // endDate is today (Day 8)
      // recentLogs range [Day 2, Day 8]
      // previousLogs range [Day -5, Day 1]
      final recentLogs = [
        DailyLog(date: 'Day 8', habitId: '1', completed: true, quality: 4),
      ];
      final previousLogs = [
        DailyLog(date: 'Day 1', habitId: '1', completed: true, quality: 3),
      ];

      expect(
        calculateQualityTrend(recentLogs: recentLogs, previousLogs: previousLogs),
        HabitQualityTrend.improving,
      );
    });
  });
}
