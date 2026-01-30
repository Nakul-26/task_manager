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
  Map<DateTime, List<DailyLog>> _events = {};
  double _successRate = 0.0;

  @override
  void initState() {
    super.initState();
    _dailyLogBox = Hive.box('dailyLogs');
    _loadLogs();
  }

  void _loadLogs() {
    final logs = _dailyLogBox.values.where((log) => log.habitId == widget.habit.id).cast<DailyLog>();
    _events = {};
    int completedDays = 0;
    for (final log in logs) {
      final date = DateTime.parse(log.date);
      if (_events[date] == null) {
        _events[date] = [];
      }
      _events[date]!.add(log);
      if (log.completed) {
        completedDays++;
      }
    }
    final totalDays = DateTime.now().difference(widget.habit.createdAt).inDays + 1;
    _successRate = totalDays > 0 ? (completedDays / totalDays) * 100 : 0;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
            TableCalendar(
              firstDay: widget.habit.createdAt,
              lastDay: DateTime.now(),
              focusedDay: DateTime.now(),
              eventLoader: (day) {
                return _events[day] ?? [];
              },
            ),
          ],
        ),
      ),
    );
  }
}
