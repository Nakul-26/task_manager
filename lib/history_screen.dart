import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:habit_tracker/models.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  HistoryScreenState createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  late Box _habitBox;
  late Box _dailyLogBox;
  Map<String, List<DailyLog>> _history = {};
  List<Habit> _habits = [];

  @override
  void initState() {
    super.initState();
    _habitBox = Hive.box('habits');
    _dailyLogBox = Hive.box('dailyLogs');
    _loadHistory();
  }

  void _loadHistory() {
    _habits = _habitBox.values.map((e) => Habit.fromMap(Map<String, dynamic>.from(e))).toList();
    var logs = _dailyLogBox.values.map((e) => DailyLog.fromMap(Map<String, dynamic>.from(e))).toList();
    
    // Group logs by date
    for (var log in logs) {
      if (_history.containsKey(log.date)) {
        _history[log.date]!.add(log);
      } else {
        _history[log.date] = [log];
      }
    }

    // Sort dates in descending order
    var sortedKeys = _history.keys.toList(growable: false)
      ..sort((a, b) => b.compareTo(a));
    _history = {for (var key in sortedKeys) key: _history[key]!};

    setState(() {});
  }

  String _getHabitName(String habitId) {
    try {
      return _habits.firstWhere((habit) => habit.id == habitId).name;
    } catch (e) {
      return 'Unknown Habit';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Habit History'),
      ),
      body: _history.isEmpty
          ? const Center(child: Text('No history yet.'))
          : ListView.builder(
              itemCount: _history.length,
              itemBuilder: (context, index) {
                String date = _history.keys.elementAt(index);
                List<DailyLog> logsForDate = _history[date]!;
                return Card(
                  margin: const EdgeInsets.all(8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          date,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...logsForDate.map((log) {
                          return ListTile(
                            title: Text(_getHabitName(log.habitId)),
                            trailing: Icon(
                              log.completed ? Icons.check_circle : Icons.cancel,
                              color: log.completed ? Colors.green : Colors.red,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
