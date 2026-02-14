import 'dart:async';

import 'package:flutter/material.dart';
import 'package:habit_tracker/history_screen.dart';
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

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  Future<void> _loadHabits() async {
    final allHabits = _habitBox.values
        .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
        .where((habit) => !habit.isArchived)
        .toList();
    _ensureSortOrder(allHabits);
    final today = _normalizeDate(DateTime.now());
    final dayOfWeek = today.weekday; // Monday = 1, Sunday = 7
    final dayOfMonth = today.day;

    _habits = allHabits.where((habit) {
      if (_normalizeDate(habit.startDate).isAfter(today)) {
        return false;
      }
      if (habit.frequency == Frequency.daily) {
        return true;
      }
      if (habit.frequency == Frequency.weekly) {
        return habit.daysOfWeek?.contains(dayOfWeek) ?? false;
      }
      if (habit.frequency == Frequency.oddDays) {
        return dayOfMonth.isOdd;
      }
      if (habit.frequency == Frequency.evenDays) {
        return dayOfMonth.isEven;
      }
      return false;
    }).toList()
      ..sort((a, b) {
        final scoreCompare = b.importanceScore.compareTo(a.importanceScore);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return a.sortOrder.compareTo(b.sortOrder);
      });

    _checkDailyReset();
    if (mounted) {
      setState(() {});
    }
  }

  void _ensureSortOrder(List<Habit> habits) {
    bool needsSave = false;
    for (int i = 0; i < habits.length; i++) {
      if (habits[i].sortOrder < 0) {
        habits[i].sortOrder = i;
        needsSave = true;
      }
    }
    if (needsSave) {
      for (final habit in habits) {
        _habitBox.put(habit.id, habit.toMap());
      }
    }
  }

  Future<void> _checkDailyReset() async {
    String today = _formatDate(DateTime.now());

    // Load completion status for today
    _dailyCompletionStatus = {};
    for (var habit in _habits) {
      var logMap = _dailyLogBox.get('${habit.id}_$today');
      if (logMap != null) {
        _dailyCompletionStatus[habit.id] =
            DailyLog.fromMap(Map<String, dynamic>.from(logMap));
      } else {
        _dailyCompletionStatus[habit.id] =
            DailyLog(date: today, habitId: habit.id);
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

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const HistoryScreen(),
      ),
    );
  }

  Future<void> _toggleHabitCompletion(Habit habit, bool? newValue) async {
    String today = _formatDate(DateTime.now());
    DailyLog log =
        _dailyCompletionStatus[habit.id] ?? DailyLog(date: today, habitId: habit.id);
    log.completed = newValue ?? false;
    await _dailyLogBox.put('${habit.id}_$today', log.toMap());
    setState(() {
      _dailyCompletionStatus[habit.id] = log;
    });
  }

  Future<void> _incrementHabitCount(Habit habit) async {
    String today = _formatDate(DateTime.now());
    DailyLog log =
        _dailyCompletionStatus[habit.id] ?? DailyLog(date: today, habitId: habit.id);
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
    DailyLog log =
        _dailyCompletionStatus[habit.id] ?? DailyLog(date: today, habitId: habit.id);
    log.count = (log.count ?? 0) > 0 ? (log.count! - 1) : 0;
    if (habit.timesPerDay != null && log.count! < habit.timesPerDay!) {
      log.completed = false;
    }
    await _dailyLogBox.put('${habit.id}_$today', log.toMap());
    setState(() {
      _dailyCompletionStatus[habit.id] = log;
    });
  }

  Future<void> _startHabitTimer(Habit habit) async {
    if ((habit.timerMinutes ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No timer set for this habit.')),
      );
      return;
    }

    final completed = await showDialog<bool>(
      context: context,
      builder: (_) => _HabitTimerDialog(
        habitName: habit.name,
        duration: Duration(minutes: habit.timerMinutes!),
      ),
    );

    if (!mounted || completed != true) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${habit.name} timer completed.')),
    );
  }

  String _formatDate(DateTime date) {
    return
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTimerLabel(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return '$hours h';
    }
    return '$hours h $remainingMinutes m';
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
    final totalDays = DateTime.now().difference(habit.startDate).inDays + 1;
    return totalDays > 0 ? (completedDays / totalDays) * 100 : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today\'s Habits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: _openHistory,
          ),
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
                          if ((habit.timerMinutes ?? 0) > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined, size: 18),
                                const SizedBox(width: 4),
                                Text(_formatTimerLabel(habit.timerMinutes!)),
                                const SizedBox(width: 12),
                                TextButton(
                                  onPressed: () => _startHabitTimer(habit),
                                  child: const Text('Start Timer'),
                                ),
                              ],
                            ),
                          ],
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

class _HabitTimerDialog extends StatefulWidget {
  final String habitName;
  final Duration duration;

  const _HabitTimerDialog({required this.habitName, required this.duration});

  @override
  State<_HabitTimerDialog> createState() => _HabitTimerDialogState();
}

class _HabitTimerDialogState extends State<_HabitTimerDialog> {
  Timer? _ticker;
  late int _remainingSeconds;
  late int _initialSeconds;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _initialSeconds = widget.duration.inSeconds;
    _remainingSeconds = _initialSeconds;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _toggleRunState() {
    if (_running) {
      _ticker?.cancel();
      setState(() {
        _running = false;
      });
      return;
    }

    setState(() {
      _running = true;
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() {
          _remainingSeconds = 0;
          _running = false;
        });
        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _remainingSeconds -= 1;
      });
    });
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _running = false;
      _remainingSeconds = _initialSeconds;
    });
  }

  String _formatRemainingTime() {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.habitName} Timer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatRemainingTime(),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _toggleRunState,
                icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                label: Text(_running ? 'Pause' : 'Start'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _reset,
                child: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
