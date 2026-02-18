import 'package:flutter/material.dart';
import 'package:habit_tracker/habit_details_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:habit_tracker/models.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  HistoryScreenState createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  late Box _habitBox;
  late Box _dailyLogBox;
  List<Habit> _habits = [];

  @override
  void initState() {
    super.initState();
    _habitBox = Hive.box('habits');
    _dailyLogBox = Hive.box('dailyLogs');
    _loadHabits();
    _habitBox.listenable().addListener(_loadHabits);
  }

  @override
  void dispose() {
    _habitBox.listenable().removeListener(_loadHabits);
    super.dispose();
  }

  void _loadHabits() {
    _habits = _habitBox.values
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
    setState(() {});
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime? _getStatsEndDateExcludingToday(Habit habit) {
    final today = _normalizeDate(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final normalizedStart = _normalizeDate(habit.startDate);
    final normalizedEndDate = habit.endDate != null
        ? _normalizeDate(habit.endDate!)
        : null;
    final statsEnd = normalizedEndDate != null && normalizedEndDate.isBefore(yesterday)
        ? normalizedEndDate
        : yesterday;
    if (statsEnd.isBefore(normalizedStart)) {
      return null;
    }
    return statsEnd;
  }

  DateTime? _parseDateString(String date) {
    final parts = date.split('-');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  int _getStreak(Habit habit) {
    final statsEnd = _getStatsEndDateExcludingToday(habit);
    if (statsEnd == null) {
      return 0;
    }
    int streak = 0;
    DateTime date = statsEnd;
    while (true) {
      final dateString = _formatDate(date);
      final logMap = _dailyLogBox.get('${habit.id}_$dateString');
      if (logMap != null) {
        final log = DailyLog.fromMap(Map<String, dynamic>.from(logMap));
        if (log.completed) {
          streak++;
          date = date.subtract(const Duration(days: 1));
        } else {
          break;
        }
      } else {
        break;
      }
    }
    return streak;
  }

  double _getSuccessRate(Habit habit) {
    final start = _normalizeDate(habit.startDate);
    final end = _getStatsEndDateExcludingToday(habit);
    if (end == null) {
      return 0;
    }
    final completedDays = _dailyLogBox.values.where((rawLog) {
      final log = Map<String, dynamic>.from(rawLog as Map);
      if (log['habitId'] != habit.id || log['completed'] != true) {
        return false;
      }
      final logDate = _parseDateString(log['date'] as String? ?? '');
      if (logDate == null) {
        return false;
      }
      final normalizedLogDate = _normalizeDate(logDate);
      return !normalizedLogDate.isBefore(start) && !normalizedLogDate.isAfter(end);
    }).length;
    final totalDays = end.difference(start).inDays + 1;
    return totalDays > 0 ? (completedDays / totalDays) * 100 : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Habit History'),
      ),
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
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 50,
                            color: habit.color,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      habit.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
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
                                Text(habit.description),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text('Streak: ${_getStreak(habit)}'),
                                    const SizedBox(width: 16),
                                    Text(
                                      'Success: ${_getSuccessRate(habit).toStringAsFixed(2)}%',
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
