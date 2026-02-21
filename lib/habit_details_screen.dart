import 'package:flutter/material.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/utils/habit_schedule_utils.dart' as schedule_utils;
import 'package:table_calendar/table_calendar.dart';
import 'package:hive/hive.dart';

class HabitDetailsScreen extends StatefulWidget {
  final Habit habit;

  const HabitDetailsScreen({super.key, required this.habit});

  @override
  State<HabitDetailsScreen> createState() => _HabitDetailsScreenState();
}

class _HabitDetailsScreenState extends State<HabitDetailsScreen> {
  late Box _dailyLogBox;
  Map<DateTime, List<DailyLog>> _completedEvents = {};
  double _successRate = 0.0;
  int _completedDays = 0;
  int _totalDays = 0;
  int _missedDays = 0;
  int _currentStreak = 0;
  int _longestStreak = 0;

  @override
  void initState() {
    super.initState();
    _dailyLogBox = Hive.box('dailyLogs');
    _loadLogs();
  }

  DateTime _normalizeDate(DateTime date) {
    return schedule_utils.normalizeDate(date);
  }

  DateTime _parseLogDate(String date) {
    final parts = date.split('-');
    if (parts.length != 3) {
      return _normalizeDate(DateTime.now());
    }
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  String _formatDate(DateTime date) {
    return schedule_utils.formatDate(date);
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return schedule_utils.isSameDate(a, b);
  }

  DateTime? _getStatsEndDate(Map<String, DailyLog> logByDate) {
    final today = _normalizeDate(DateTime.now());
    final normalizedStart = _normalizeDate(widget.habit.startDate);
    final normalizedEndDate = widget.habit.endDate != null
        ? _normalizeDate(widget.habit.endDate!)
        : null;
    final statsEnd = normalizedEndDate != null && normalizedEndDate.isBefore(today)
        ? normalizedEndDate
        : today;
    final todayKey = _formatDate(today);
    final isTodayCompleted = logByDate[todayKey]?.completed ?? false;
    final shouldExcludeToday =
        _isSameDate(statsEnd, today) &&
        schedule_utils.isScheduledDay(widget.habit, today) &&
        !isTodayCompleted;
    final effectiveStatsEnd = shouldExcludeToday
        ? statsEnd.subtract(const Duration(days: 1))
        : statsEnd;
    if (effectiveStatsEnd.isBefore(normalizedStart)) {
      return null;
    }
    return effectiveStatsEnd;
  }

  void _loadLogs() {
    final start = _normalizeDate(widget.habit.startDate);
    final logs = _dailyLogBox.values
        .map((e) => DailyLog.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((log) => log.habitId == widget.habit.id);
    _completedEvents = {};
    _completedDays = 0;
    final logByDate = <String, DailyLog>{};
    for (final log in logs) {
      final normalizedLogDate = _normalizeDate(_parseLogDate(log.date));
      logByDate[log.date] = log;
      if (log.completed) {
        if (_completedEvents[normalizedLogDate] == null) {
          _completedEvents[normalizedLogDate] = [];
        }
        _completedEvents[normalizedLogDate]!.add(log);
      }
    }
    final statsEnd = _getStatsEndDate(logByDate);
    if (statsEnd == null) {
      _totalDays = 0;
      _missedDays = 0;
      _successRate = 0;
      _currentStreak = 0;
      _longestStreak = 0;
      setState(() {});
      return;
    }
    DateTime date = start;
    _totalDays = 0;
    _completedDays = 0;
    while (!date.isAfter(statsEnd)) {
      if (schedule_utils.isScheduledDay(widget.habit, date)) {
        _totalDays++;
        final key = _formatDate(date);
        if (logByDate[key]?.completed == true) {
          _completedDays++;
        }
      }
      date = date.add(const Duration(days: 1));
    }
    _missedDays = (_totalDays - _completedDays).clamp(0, _totalDays);
    _successRate = _totalDays > 0 ? (_completedDays / _totalDays) * 100 : 0;
    _currentStreak = _computeCurrentStreak(logByDate, statsEnd);
    _longestStreak = _computeLongestStreak(logByDate, statsEnd);
    setState(() {});
  }

  int _computeCurrentStreak(
    Map<String, DailyLog> logByDate,
    DateTime effectiveToday,
  ) {
    int streak = 0;
    final start = _normalizeDate(widget.habit.startDate);
    DateTime date = _normalizeDate(effectiveToday);
    while (!date.isBefore(start)) {
      if (!schedule_utils.isScheduledDay(widget.habit, date)) {
        date = date.subtract(const Duration(days: 1));
        continue;
      }
      final key = _formatDate(date);
      final log = logByDate[key];
      if (log != null && log.completed) {
        streak++;
        date = date.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  int _computeLongestStreak(
    Map<String, DailyLog> logByDate,
    DateTime effectiveToday,
  ) {
    int longest = 0;
    int streak = 0;
    DateTime date = _normalizeDate(widget.habit.startDate);
    final end = _normalizeDate(effectiveToday);
    while (!date.isAfter(end)) {
      if (!schedule_utils.isScheduledDay(widget.habit, date)) {
        date = date.add(const Duration(days: 1));
        continue;
      }
      final key = _formatDate(date);
      final log = logByDate[key];
      if (log != null && log.completed) {
        streak++;
        if (streak > longest) {
          longest = streak;
        }
      } else {
        streak = 0;
      }
      date = date.add(const Duration(days: 1));
    }
    return longest;
  }

  @override
  Widget build(BuildContext context) {
    final normalizedStartDate = _normalizeDate(widget.habit.startDate);
    final today = _normalizeDate(DateTime.now());
    final normalizedEndDate = widget.habit.endDate != null
        ? _normalizeDate(widget.habit.endDate!)
        : null;
    final effectiveToday = normalizedEndDate != null && normalizedEndDate.isBefore(today)
        ? normalizedEndDate
        : today;
    final calendarLastDay = normalizedStartDate.isAfter(effectiveToday)
        ? normalizedStartDate
        : effectiveToday;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.habit.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.habit.description,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            Text(
              'Success Rate: ${_successRate.toStringAsFixed(2)}%',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text('Start Date: ${_formatDate(normalizedStartDate)}'),
            if (normalizedEndDate != null) Text('End Date: ${_formatDate(normalizedEndDate)}'),
            Text('Completed Days: $_completedDays'),
            Text('Missed Days: $_missedDays'),
            Text('Current Streak: $_currentStreak'),
            Text('Longest Streak: $_longestStreak'),
            const SizedBox(height: 20),
            TableCalendar(
              firstDay: normalizedStartDate,
              lastDay: calendarLastDay,
              focusedDay: calendarLastDay,
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  // ignore: deprecated_member_use
                  color: widget.habit.color.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: widget.habit.color,
                  shape: BoxShape.circle,
                ),
                markerDecoration: BoxDecoration(
                  color: widget.habit.color,
                  shape: BoxShape.circle,
                ),
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: widget.habit.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
              eventLoader: (day) {
                final key = _normalizeDate(day);
                return _completedEvents[key] ?? [];
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: widget.habit.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Completed day'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
