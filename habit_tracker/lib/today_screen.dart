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
  Map<String, DailyLog> _dailyCompletionStatus = {};

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
    final allHabits = _habitBox.values.map((e) => Habit.fromMap(Map<String, dynamic>.from(e))).toList();
    final today = DateTime.now();
    final dayOfWeek = today.weekday; // Monday = 1, Sunday = 7

    _habits = allHabits.where((habit) {
      if (habit.frequency == Frequency.daily) {
        return true;
      }
      if (habit.frequency == Frequency.weekly) {
        return habit.daysOfWeek?.contains(dayOfWeek) ?? false;
      }
      return false;
    }).toList();

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
      var logMap = _dailyLogBox.get('${habit.id}_$today');
      if (logMap != null) {
        _dailyCompletionStatus[habit.id] = DailyLog.fromMap(Map<String, dynamic>.from(logMap));
      } else {
        _dailyCompletionStatus[habit.id] = DailyLog(date: today, habitId: habit.id);
      }
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
    DailyLog log = _dailyCompletionStatus[habit.id] ?? DailyLog(date: today, habitId: habit.id);
    log.completed = newValue ?? false;
    await _dailyLogBox.put('${habit.id}_$today', log.toMap());
    setState(() {
      _dailyCompletionStatus[habit.id] = log;
    });
  }

  Future<void> _incrementHabitCount(Habit habit) async {
    String today = _formatDate(DateTime.now());
    DailyLog log = _dailyCompletionStatus[habit.id] ?? DailyLog(date: today, habitId: habit.id);
    log.count = (log.count ?? 0) + 1;
    if (habit.timesPerDay != null && log.count! >= habit.timesPerDay!) {
      log.completed = true;
    }
    await _dailyLogBox.put('${habit.id}_$today', log.toMap());
    setState(() {
      _dailyCompletionStatus[habit.id] = log;
    });
  }

  Future<void> _decrementHabitCount(Habit habit) async {
    String today = _formatDate(DateTime.now());
    DailyLog log = _dailyCompletionStatus[habit.id] ?? DailyLog(date: today, habitId: habit.id);
    log.count = (log.count ?? 0) > 0 ? (log.count! - 1) : 0;
    if (habit.timesPerDay != null && log.count! < habit.timesPerDay!) {
      log.completed = false;
    }
    await _dailyLogBox.put('${habit.id}_$today', log.toMap());
    setState(() {
      _dailyCompletionStatus[habit.id] = log;
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
          final log = _dailyCompletionStatus[habit.id]!;
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
                    if (habit.type == HabitType.binary)
                      Checkbox(
                        value: log.completed,
                        onChanged: (value) {
                          _toggleHabitCompletion(habit, value);
                        },
                      ),
                    if (habit.type == HabitType.counted)
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () => _decrementHabitCount(habit),
                          ),
                          Text('${log.count ?? 0} / ${habit.timesPerDay ?? ''}'),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () => _incrementHabitCount(habit),
                          ),
                        ],
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
