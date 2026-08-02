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

    test('qualityScoreLabel and qualityScoreStars return correct values', () {
      expect(qualityScoreLabel(1.2), 'Poor');
      expect(qualityScoreStars(1.2), '⭐☆☆☆');

      expect(qualityScoreLabel(2.0), 'Average');
      expect(qualityScoreStars(2.0), '⭐⭐☆☆');

      expect(qualityScoreLabel(3.2), 'Good');
      expect(qualityScoreStars(3.2), '⭐⭐⭐☆');

      expect(qualityScoreLabel(3.8), 'Excellent');
      expect(qualityScoreStars(3.8), '⭐⭐⭐⭐');
    });

    test('calculateQualityTrendFromRatedLogs returns stable for consistent Poor ratings', () {
      final logs = [
        DailyLog(date: '2026-04-01', habitId: '1', completed: true, quality: 1),
        DailyLog(date: '2026-04-02', habitId: '1', completed: true, quality: 1),
        DailyLog(date: '2026-04-03', habitId: '1', completed: true, quality: 1),
      ];
      expect(
        calculateQualityTrendFromRatedLogs(logs),
        HabitQualityTrend.stable,
      );
    });

    test('calculateQualityTrendFromRatedLogs detects improvement above threshold', () {
      final logs = [
        DailyLog(date: '2026-04-01', habitId: '1', completed: true, quality: 1),
        DailyLog(date: '2026-04-02', habitId: '1', completed: true, quality: 2),
        DailyLog(date: '2026-04-03', habitId: '1', completed: true, quality: 3),
        DailyLog(date: '2026-04-04', habitId: '1', completed: true, quality: 4),
      ];
      expect(
        calculateQualityTrendFromRatedLogs(logs),
        HabitQualityTrend.improving,
      );
    });
  });
}
