import 'package:flutter/material.dart';
import 'package:habit_tracker/habit_details_screen.dart';
import 'package:habit_tracker/manage_habits_screen.dart';
import 'package:habit_tracker/models.dart';
import 'package:hive_flutter/hive_flutter.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Box _habitBox;
  late Box _dailyLogBox;
  List<Habit> _habits = [];
  Map<String, bool> _dailyCompletionStatus = {};

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

  Future<void> _loadHabits() async {
    _habits = _habitBox.values.map((e) => Habit.fromMap(Map<String, dynamic>.from(e))).toList();
    _checkDailyReset();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkDailyReset() async {
    String today = _formatDate(DateTime.now());

    // Load completion status for today
    _dailyCompletionStatus = {};
    for (var habit in _habits) {
      var log = _dailyLogBox.get('${habit.id}_$today');
      _dailyCompletionStatus[habit.id] = log != null ? log['completed'] as bool : false;
    }
  }

  void _manageHabits() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ManageHabitsScreen(),
      ),
    );
  }

  Future<void> _toggleHabitCompletion(Habit habit, bool? newValue) async {
    String today = _formatDate(DateTime.now());
    DailyLog log = DailyLog(
      date: today,
      habitId: habit.id,
      completed: newValue ?? false,
    );
    await _dailyLogBox.put('${habit.id}_$today', log.toMap());
    setState(() {
      _dailyCompletionStatus[habit.id] = newValue ?? false;
    });
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  int _getStreak(Habit habit) {
    int streak = 0;
    DateTime date = DateTime.now();
    while (true) {
      final dateString = _formatDate(date);
      final log = _dailyLogBox.get('${habit.id}_$dateString');
      if (log != null && log['completed'] as bool) {
        streak++;
        date = date.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  double _getSuccessRate(Habit habit) {
    final logs = _dailyLogBox.values.where((log) => log['habitId'] == habit.id);
    final completedDays = logs.where((log) => log['completed'] as bool).length;
    final totalDays = DateTime.now().difference(habit.createdAt).inDays + 1;
    return totalDays > 0 ? (completedDays / totalDays) * 100 : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today\'s Habits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _manageHabits,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _habits.length,
        itemBuilder: (context, index) {
          final habit = _habits[index];
          bool isCompleted = _dailyCompletionStatus[habit.id] ?? false;
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
                                const Icon(Icons.star, color: Colors.amber, size: 20),
                              ]
                            ],
                          ),
                          Text(habit.description),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text('Streak: ${_getStreak(habit)}'),
                              const SizedBox(width: 16),
                              Text('Success: ${_getSuccessRate(habit).toStringAsFixed(2)}%'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Checkbox(
                      value: isCompleted,
                      onChanged: (value) {
                        _toggleHabitCompletion(habit, value);
                      },
                    ),
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

