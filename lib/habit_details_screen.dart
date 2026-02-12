import 'package:flutter/material.dart';
import 'package:habit_tracker/models.dart';
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
    return DateTime(date.year, date.month, date.day);
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
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _loadLogs() {
    final logs = _dailyLogBox.values
        .map((e) => DailyLog.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((log) => log.habitId == widget.habit.id);
    _completedEvents = {};
    _completedDays = 0;
    final logByDate = <String, DailyLog>{};
    for (final log in logs) {
      logByDate[log.date] = log;
      if (log.completed) {
        _completedDays++;
        final date = _normalizeDate(_parseLogDate(log.date));
        if (_completedEvents[date] == null) {
          _completedEvents[date] = [];
        }
        _completedEvents[date]!.add(log);
      }
    }
    final today = _normalizeDate(DateTime.now());
    final start = _normalizeDate(widget.habit.startDate);
    _totalDays = today.difference(start).inDays + 1;
    if (_totalDays < 0) {
      _totalDays = 0;
    }
    _missedDays = (_totalDays - _completedDays).clamp(0, _totalDays);
    _successRate = _totalDays > 0 ? (_completedDays / _totalDays) * 100 : 0;
    _currentStreak = _computeCurrentStreak(logByDate);
    _longestStreak = _computeLongestStreak(logByDate);
    setState(() {});
  }

  int _computeCurrentStreak(Map<String, DailyLog> logByDate) {
    int streak = 0;
    DateTime date = _normalizeDate(DateTime.now());
    while (true) {
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

  int _computeLongestStreak(Map<String, DailyLog> logByDate) {
    int longest = 0;
    int streak = 0;
    DateTime date = _normalizeDate(widget.habit.startDate);
    final end = _normalizeDate(DateTime.now());
    while (!date.isAfter(end)) {
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
    final calendarLastDay = normalizedStartDate.isAfter(today)
        ? normalizedStartDate
        : today;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.habit.name),
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
