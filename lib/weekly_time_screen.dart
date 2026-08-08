import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/utils/habit_schedule_utils.dart' as schedule_utils;
import 'package:habit_tracker/utils/time_budget_utils.dart';
import 'package:hive_flutter/hive_flutter.dart';

const List<String> _weekdayShortNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class WeeklyTimeScreen extends StatefulWidget {
  const WeeklyTimeScreen({super.key});

  @override
  State<WeeklyTimeScreen> createState() => _WeeklyTimeScreenState();
}

class _WeeklyTimeScreenState extends State<WeeklyTimeScreen> {
  late Box<dynamic> _habitBox;
  late Box<dynamic> _settingsBox;
  late ValueListenable<Box<dynamic>> _habitListenable;
  late ValueListenable<Box<dynamic>> _settingsListenable;
  List<Habit> _habits = [];
  int? _dailyLimitMinutes;
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _habitBox = Hive.box(HiveBoxNames.habits);
    _settingsBox = Hive.box(HiveBoxNames.appSettings);
    _habitListenable = _habitBox.listenable();
    _settingsListenable = _settingsBox.listenable();
    _weekStart = _mondayOf(schedule_utils.normalizeDate(DateTime.now()));
    _loadHabits();
    _loadSettings();
    _habitListenable.addListener(_loadHabits);
    _settingsListenable.addListener(_loadSettings);
  }

  @override
  void dispose() {
    _habitListenable.removeListener(_loadHabits);
    _settingsListenable.removeListener(_loadSettings);
    super.dispose();
  }

  DateTime _mondayOf(DateTime date) {
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }

  void _loadHabits() {
    final habits = _habitBox.values
        .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
        .where((habit) => !habit.isArchived)
        .toList();
    if (mounted) {
      setState(() {
        _habits = habits;
      });
    }
  }

  void _loadSettings() {
    final limit = loadDailyTimeLimitMinutes(_settingsBox);
    if (mounted) {
      setState(() {
        _dailyLimitMinutes = limit;
      });
    }
  }

  void _goToPreviousWeek() {
    setState(() {
      _weekStart = _weekStart.subtract(const Duration(days: 7));
    });
  }

  void _goToNextWeek() {
    setState(() {
      _weekStart = _weekStart.add(const Duration(days: 7));
    });
  }

  void _goToCurrentWeek() {
    setState(() {
      _weekStart = _mondayOf(schedule_utils.normalizeDate(DateTime.now()));
    });
  }

  Future<void> _editDailyLimit() async {
    final controller = TextEditingController(
      text: _dailyLimitMinutes?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<int?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Daily time limit'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Minutes per day',
              helperText: 'Leave blank to remove the limit and warnings.',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return null;
              }
              final parsed = int.tryParse(value.trim());
              if (parsed == null || parsed <= 0) {
                return 'Enter a number greater than 0';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                final text = controller.text.trim();
                Navigator.of(dialogContext).pop(
                  text.isEmpty ? null : int.parse(text),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null && (_dailyLimitMinutes == null)) {
      return;
    }
    await saveDailyTimeLimitMinutes(_settingsBox, result);
  }

  void _openDay(DateTime date) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DayHabitsScreen(
          date: date,
          habits: _habits,
          dailyLimitMinutes: _dailyLimitMinutes,
        ),
      ),
    );
  }

  String _formatWeekRange(DateTime start, DateTime end) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final startLabel = '${months[start.month - 1]} ${start.day}';
    final endLabel = '${months[end.month - 1]} ${end.day}';
    return '$startLabel - $endLabel, ${end.year}';
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final today = schedule_utils.normalizeDate(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Time Budget'),
        actions: [
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            tooltip: 'Set daily time limit',
            onPressed: _editDailyLimit,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous week',
                  onPressed: _goToPreviousWeek,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _goToCurrentWeek,
                    child: Column(
                      children: [
                        Text(
                          _formatWeekRange(_weekStart, weekEnd),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _dailyLimitMinutes == null
                              ? 'No daily limit set'
                              : 'Daily limit: ${formatMinutesLabel(_dailyLimitMinutes!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next week',
                  onPressed: _goToNextWeek,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: 7,
              itemBuilder: (context, index) {
                final date = _weekStart.add(Duration(days: index));
                final scheduledHabits = habitsScheduledOnDate(_habits, date);
                final totalMinutes = scheduledHabits.fold<int>(
                  0,
                  (sum, habit) => sum + (habit.timerMinutes ?? 0),
                );
                final exceedsLimit = _dailyLimitMinutes != null &&
                    totalMinutes > _dailyLimitMinutes!;
                final isToday = schedule_utils.isSameDate(date, today);

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  color: exceedsLimit
                      ? Colors.red.withValues(alpha: 0.08)
                      : null,
                  shape: isToday
                      ? RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1.5,
                          ),
                        )
                      : null,
                  child: ListTile(
                    onTap: () => _openDay(date),
                    title: Row(
                      children: [
                        Text(
                          _weekdayShortNames[index],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          schedule_utils.formatDate(date),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(width: 8),
                          const Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '${scheduledHabits.length} habit${scheduledHabits.length == 1 ? '' : 's'}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatMinutesLabel(totalMinutes),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: exceedsLimit ? Colors.red : null,
                          ),
                        ),
                        if (exceedsLimit)
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.red, size: 14),
                              SizedBox(width: 2),
                              Text(
                                'Over limit',
                                style: TextStyle(color: Colors.red, fontSize: 11),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DayHabitsScreen extends StatelessWidget {
  final DateTime date;
  final List<Habit> habits;
  final int? dailyLimitMinutes;

  const DayHabitsScreen({
    super.key,
    required this.date,
    required this.habits,
    required this.dailyLimitMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final scheduledHabits = habitsScheduledOnDate(habits, date)
      ..sort((a, b) => (b.timerMinutes ?? 0).compareTo(a.timerMinutes ?? 0));
    final totalMinutes = scheduledHabits.fold<int>(
      0,
      (sum, habit) => sum + (habit.timerMinutes ?? 0),
    );
    final exceedsLimit =
        dailyLimitMinutes != null && totalMinutes > dailyLimitMinutes!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_weekdayShortNames[date.weekday - 1]}, ${schedule_utils.formatDate(date)}',
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: exceedsLimit
                ? Colors.red.withValues(alpha: 0.1)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total time required: ${formatMinutesLabel(totalMinutes)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (dailyLimitMinutes != null)
                  Text(
                    'Daily limit: ${formatMinutesLabel(dailyLimitMinutes!)}',
                  ),
                if (exceedsLimit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This day exceeds your daily time limit by '
                            '${formatMinutesLabel(totalMinutes - dailyLimitMinutes!)}.',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: scheduledHabits.isEmpty
                ? const Center(child: Text('No habits scheduled for this day.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    itemCount: scheduledHabits.length,
                    itemBuilder: (context, index) {
                      final habit = scheduledHabits[index];
                      final minutes = habit.timerMinutes;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: Container(width: 8, color: habit.color),
                          title: Text(habit.name),
                          subtitle: habit.description.trim().isEmpty
                              ? null
                              : Text(
                                  habit.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: Text(
                            minutes == null || minutes <= 0
                                ? 'No time set'
                                : formatMinutesLabel(minutes),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: minutes == null || minutes <= 0
                                  ? Theme.of(context).colorScheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
