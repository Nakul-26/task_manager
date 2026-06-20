import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/habit_details_screen.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/utils/habit_schedule_utils.dart'
    as schedule_utils;
import 'package:habit_tracker/utils/pause_utils.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  HistoryScreenState createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  late Box _habitBox;
  late Box _dailyLogBox;
  late Box _settingsBox;
  late ValueListenable<Box> _dailyLogListenable;
  List<Habit> _habits = [];
  List<PausePeriod> _pausePeriods = [];

  // Cached statistics to improve performance
  final Map<String, int> _cachedStreaks = {};
  final Map<String, double> _cachedSuccessRates = {};

  @override
  void initState() {
    super.initState();
    _habitBox = Hive.box(HiveBoxNames.habits);
    _dailyLogBox = Hive.box(HiveBoxNames.dailyLogs);
    _settingsBox = Hive.box(HiveBoxNames.appSettings);
    _dailyLogListenable = _dailyLogBox.listenable();
    _loadHabits();
    _habitBox.listenable().addListener(_loadHabits);
    _settingsBox.listenable().addListener(_loadPausePeriods);
    _dailyLogListenable.addListener(_loadHabits);
    _loadPausePeriods();
  }

  @override
  void dispose() {
    _habitBox.listenable().removeListener(_loadHabits);
    _settingsBox.listenable().removeListener(_loadPausePeriods);
    _dailyLogListenable.removeListener(_loadHabits);
    super.dispose();
  }

  void _loadHabits() {
    _habits =
        _habitBox.values
            .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
            .where((habit) => !habit.isArchived)
            .toList()
          ..sort((a, b) {
            final scoreCompare = b.importanceScore.compareTo(a.importanceScore);
            if (scoreCompare != 0) {
              return scoreCompare;
            }
            return a.sortOrder.compareTo(b.sortOrder);
          });
    _calculateAllStats();
    if (mounted) {
      setState(() {});
    }
  }

  void _calculateAllStats() {
    _cachedStreaks.clear();
    _cachedSuccessRates.clear();
    for (final habit in _habits) {
      _cachedStreaks[habit.id] = _getStreak(habit);
      _cachedSuccessRates[habit.id] = _getSuccessRate(habit);
    }
  }

  void _loadPausePeriods() {
    _pausePeriods = loadPausePeriods(_settingsBox);
    if (mounted) {
      setState(() {});
    }
  }

  String _formatDate(DateTime date) {
    return schedule_utils.formatDate(date);
  }

  DateTime _normalizeDate(DateTime date) {
    return schedule_utils.normalizeDate(date);
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return schedule_utils.isSameDate(a, b);
  }

  bool _isHabitCompletedOnDate(Habit habit, DateTime date) {
    final dateString = _formatDate(_normalizeDate(date));
    final logMap = _dailyLogBox.get('${habit.id}_$dateString');
    if (logMap == null) {
      return false;
    }
    final log = DailyLog.fromMap(Map<String, dynamic>.from(logMap));
    return log.completed;
  }

  DateTime? _getStatsEndDate(Habit habit) {
    final today = _normalizeDate(DateTime.now());
    final normalizedStart = _normalizeDate(habit.startDate);
    final normalizedEndDate = habit.endDate != null
        ? _normalizeDate(habit.endDate!)
        : null;
    final statsEnd =
        normalizedEndDate != null && normalizedEndDate.isBefore(today)
        ? normalizedEndDate
        : today;
    final shouldExcludeToday =
        _isSameDate(statsEnd, today) &&
        !isPausedOnDate(_pausePeriods, today) &&
        schedule_utils.isScheduledDay(habit, today) &&
        !_isHabitCompletedOnDate(habit, today);
    final effectiveStatsEnd = shouldExcludeToday
        ? statsEnd.subtract(const Duration(days: 1))
        : statsEnd;
    if (effectiveStatsEnd.isBefore(normalizedStart)) {
      return null;
    }
    return effectiveStatsEnd;
  }

  int _getStreak(Habit habit) {
    final statsEnd = _getStatsEndDate(habit);
    if (statsEnd == null) {
      return 0;
    }
    int streak = 0;
    final normalizedStart = _normalizeDate(habit.startDate);
    DateTime date = statsEnd;
    while (!date.isBefore(normalizedStart)) {
      if (isPausedOnDate(_pausePeriods, date)) {
        date = date.subtract(const Duration(days: 1));
        continue;
      }
      if (!schedule_utils.isScheduledDay(habit, date)) {
        date = date.subtract(const Duration(days: 1));
        continue;
      }
      if (_isHabitCompletedOnDate(habit, date)) {
        streak++;
        date = date.subtract(const Duration(days: 1));
        continue;
      }
      break;
    }
    return streak;
  }

  double _getSuccessRate(Habit habit) {
    final start = _normalizeDate(habit.startDate);
    final end = _getStatsEndDate(habit);
    if (end == null) {
      return 0;
    }
    int completedScheduledDays = 0;
    int totalScheduledDays = 0;
    DateTime date = start;
    while (!date.isAfter(end)) {
      if (isPausedOnDate(_pausePeriods, date)) {
        date = date.add(const Duration(days: 1));
        continue;
      }
      if (schedule_utils.isScheduledDay(habit, date)) {
        totalScheduledDays++;
        if (_isHabitCompletedOnDate(habit, date)) {
          completedScheduledDays++;
        }
      }
      date = date.add(const Duration(days: 1));
    }
    return totalScheduledDays > 0
        ? (completedScheduledDays / totalScheduledDays) * 100
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Habit History')),
      body: _habits.isEmpty
          ? const Center(child: Text('No habits to show.'))
          : ListView.builder(
              itemCount: _habits.length,
              itemBuilder: (context, index) {
                final habit = _habits[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => HabitDetailsScreen(habit: habit),
                      ),
                    );
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(width: 10, height: 50, color: habit.color),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        habit.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (habit.isImportant) ...[
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.star,
                                        color: Colors.amber,
                                        size: 20,
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  habit.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text('Streak: ${_cachedStreaks[habit.id] ?? 0}'),
                                    const SizedBox(width: 16),
                                    Text(
                                      'Success: ${(_cachedSuccessRates[habit.id] ?? 0.0).toStringAsFixed(2)}%',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
