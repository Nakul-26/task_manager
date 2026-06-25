import 'package:flutter/material.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:habit_tracker/utils/habit_quality_utils.dart';
import 'package:habit_tracker/utils/habit_schedule_utils.dart'
    as schedule_utils;
import 'package:habit_tracker/utils/pause_utils.dart';
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
  late Box _settingsBox;
  late Box _habitBox;
  Map<DateTime, List<DailyLog>> _completedEvents = {};
  Map<DateTime, List<PausePeriod>> _pausedEvents = {};
  List<PausePeriod> _pausePeriods = [];
  double _successRate = 0.0;
  int _completedDays = 0;
  int _totalDays = 0;
  int _missedDays = 0;
  int _currentStreak = 0;
  int _longestStreak = 0;
  double? _averageQuality;
  double? _recentAverageQuality;
  double? _previousAverageQuality;
  int? _latestQuality;
  int? _previousLoggedQuality;
  int? _bestQuality;
  HabitQualityTrend _qualityTrend = HabitQualityTrend.insufficientData;

  @override
  void initState() {
    super.initState();
    _dailyLogBox = Hive.box(HiveBoxNames.dailyLogs);
    _settingsBox = Hive.box(HiveBoxNames.appSettings);
    _habitBox = Hive.box(HiveBoxNames.habits);
    _loadLogs();
  }

  DateTime _normalizeDate(DateTime date) {
    return schedule_utils.normalizeDate(date);
  }

  bool _isHabitPaused(DateTime date) {
    return isPausedOnDate(_pausePeriods, date) ||
        isPausedOnDate(widget.habit.pausePeriods, date);
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
    final statsEnd =
        normalizedEndDate != null && normalizedEndDate.isBefore(today)
        ? normalizedEndDate
        : today;
    final todayKey = _formatDate(today);
    final isTodayCompleted = logByDate[todayKey]?.completed ?? false;
    final shouldExcludeToday =
        _isSameDate(statsEnd, today) &&
        !_isHabitPaused(today) &&
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

  List<DailyLog> _getCompletedLogsForRange(
    Map<String, DailyLog> logByDate,
    DateTime endDate, {
    required int days,
  }) {
    final logs = <DailyLog>[];
    final normalizedEnd = _normalizeDate(endDate);
    final startDate = normalizedEnd.subtract(Duration(days: days - 1));
    DateTime date = startDate;
    while (!date.isAfter(normalizedEnd)) {
      if (_isHabitPaused(date) ||
          !schedule_utils.isScheduledDay(widget.habit, date)) {
        date = date.add(const Duration(days: 1));
        continue;
      }
      final log = logByDate[_formatDate(date)];
      if (log != null && log.completed) {
        logs.add(log);
      }
      date = date.add(const Duration(days: 1));
    }
    return logs;
  }

  List<DailyLog> _getCompletedLogsInOrder(Map<String, DailyLog> logByDate) {
    final logs = logByDate.values.where((log) => log.completed).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return logs;
  }

  void _loadLogs() {
    final start = _normalizeDate(widget.habit.startDate);
    _pausePeriods = loadPausePeriods(_settingsBox);
    final logs = _dailyLogBox.values
        .map((e) => DailyLog.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((log) => log.habitId == widget.habit.id);
    _completedEvents = {};
    _pausedEvents = {};
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
    for (final period in _pausePeriods) {
      DateTime day = _normalizeDate(period.startDate);
      final normalizedEnd = _normalizeDate(period.endDate);
      while (!day.isAfter(normalizedEnd)) {
        _pausedEvents.putIfAbsent(day, () => []).add(period);
        day = day.add(const Duration(days: 1));
      }
    }
    for (final period in widget.habit.pausePeriods) {
      DateTime day = _normalizeDate(period.startDate);
      final normalizedEnd = _normalizeDate(period.endDate);
      while (!day.isAfter(normalizedEnd)) {
        _pausedEvents.putIfAbsent(day, () => []).add(period);
        day = day.add(const Duration(days: 1));
      }
    }
    final statsEnd = _getStatsEndDate(logByDate);
    if (statsEnd == null) {
      _totalDays = 0;
      _missedDays = 0;
      _successRate = 0;
      _currentStreak = 0;
      _longestStreak = 0;
      _averageQuality = null;
      _recentAverageQuality = null;
      _previousAverageQuality = null;
      _latestQuality = null;
      _previousLoggedQuality = null;
      _bestQuality = null;
      _qualityTrend = HabitQualityTrend.insufficientData;
      setState(() {});
      return;
    }
    DateTime date = start;
    _totalDays = 0;
    _completedDays = 0;
    while (!date.isAfter(statsEnd)) {
      if (_isHabitPaused(date)) {
        date = date.add(const Duration(days: 1));
        continue;
      }
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
    final completedLogs = _getCompletedLogsInOrder(logByDate);
    _averageQuality = averageQuality(completedLogs);
    final recentLogs = _getCompletedLogsForRange(logByDate, statsEnd, days: 14);
    final previousLogs = _getCompletedLogsForRange(
      logByDate,
      statsEnd.subtract(const Duration(days: 14)),
      days: 14,
    );
    _recentAverageQuality = averageQuality(recentLogs);
    _previousAverageQuality = averageQuality(previousLogs);
    _qualityTrend = calculateQualityTrend(
      recentLogs: recentLogs,
      previousLogs: previousLogs,
    );
    final ratedLogs = completedLogs
        .where((log) => log.quality != null)
        .toList();
    _bestQuality = ratedLogs.isEmpty
        ? null
        : ratedLogs.map((log) => log.quality!).reduce((a, b) => a > b ? a : b);
    _latestQuality = ratedLogs.isEmpty ? null : ratedLogs.last.quality;
    _previousLoggedQuality = ratedLogs.length > 1
        ? ratedLogs[ratedLogs.length - 2].quality
        : null;
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
      if (_isHabitPaused(date)) {
        date = date.subtract(const Duration(days: 1));
        continue;
      }
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
      if (_isHabitPaused(date)) {
        date = date.add(const Duration(days: 1));
        continue;
      }
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

  String? _buildDailyFeedback() {
    final latest = _latestQuality;
    final previous = _previousLoggedQuality;
    if (latest == null || previous == null) {
      return null;
    }
    if (latest > previous) {
      return 'Better than last time';
    }
    if (latest < previous) {
      return 'Worse than last time';
    }
    return 'Same as last time';
  }

  @override
  Widget build(BuildContext context) {
    final normalizedStartDate = _normalizeDate(widget.habit.startDate);
    final today = _normalizeDate(DateTime.now());
    final normalizedEndDate = widget.habit.endDate != null
        ? _normalizeDate(widget.habit.endDate!)
        : null;
    final effectiveToday =
        normalizedEndDate != null && normalizedEndDate.isBefore(today)
        ? normalizedEndDate
        : today;
    final calendarLastDay = normalizedStartDate.isAfter(effectiveToday)
        ? normalizedStartDate
        : effectiveToday;
    final dailyFeedback = _buildDailyFeedback();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.habit.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(widget.habit.description, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 20),
          Text(
            'Success Rate: ${_successRate.toStringAsFixed(2)}%',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            _averageQuality == null
                ? 'Average Quality: Unrated'
                : 'Average Quality: ${_averageQuality!.toStringAsFixed(1)} / 4',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Trend: '),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: qualityTrendColor(_qualityTrend).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: qualityTrendColor(_qualityTrend).withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  qualityTrendLabel(_qualityTrend),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: qualityTrendColor(_qualityTrend),
                  ),
                ),
              ),
            ],
          ),
          if (_recentAverageQuality != null)
            Text(
              'Last 14 days: ${_recentAverageQuality!.toStringAsFixed(1)} / 4',
            ),
          if (_previousAverageQuality != null)
            Text(
              'Previous 14 days: ${_previousAverageQuality!.toStringAsFixed(1)} / 4',
            ),
          if (_bestQuality != null)
            Text('Best quality ever: ${qualityLabel(_bestQuality!)}'),
          if (dailyFeedback != null) Text(dailyFeedback),
          const SizedBox(height: 20),
          Text('Start Date: ${_formatDate(normalizedStartDate)}'),
          if (normalizedEndDate != null)
            Text('End Date: ${_formatDate(normalizedEndDate)}'),
          Text('Completed Days: $_completedDays'),
          Text('Missed Days: $_missedDays'),
          Text('Current Streak: $_currentStreak'),
          Text('Longest Streak: $_longestStreak'),
          const SizedBox(height: 20),
          TableCalendar(
            firstDay: normalizedStartDate,
            lastDay: calendarLastDay,
            focusedDay: calendarLastDay,
            availableGestures: AvailableGestures.horizontalSwipe,
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: widget.habit.color.withValues(alpha: 0.25),
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
                final normalizedDay = _normalizeDate(day);
                if (events.isEmpty &&
                    (_pausedEvents[normalizedDay]?.isEmpty ?? true)) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_pausedEvents[normalizedDay]?.isNotEmpty ?? false)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                      if ((_pausedEvents[normalizedDay]?.isNotEmpty ?? false) &&
                          events.isNotEmpty)
                        const SizedBox(width: 4),
                      if (events.isNotEmpty)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: widget.habit.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                );
              },
              defaultBuilder: (context, day, focusedDay) {
                final normalizedDay = _normalizeDate(day);
                if (!(_pausedEvents[normalizedDay]?.isNotEmpty ?? false)) {
                  return null;
                }
                return Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.orange.shade300),
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
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text('Paused day'),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 10),
          _buildPausePeriodsSection(),
        ],
      ),
    );
  }

  String _formatHumanDate(BuildContext context, DateTime date) {
    return MaterialLocalizations.of(
      context,
    ).formatMediumDate(_normalizeDate(date));
  }

  String _statusLabel(PausePeriod period) {
    final today = _normalizeDate(DateTime.now());
    if (!period.startDate.isAfter(today) && !period.endDate.isBefore(today)) {
      return 'Active';
    }
    if (period.startDate.isAfter(today)) {
      return 'Upcoming';
    }
    return 'Past';
  }

  MaterialColor _statusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.orange;
      case 'Upcoming':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Future<void> _openPauseDialog({PausePeriod? period, int? index}) async {
    final today = _normalizeDate(DateTime.now());
    DateTime startDate = period?.startDate ?? today;
    DateTime endDate = period?.endDate ?? today;
    final descriptionController = TextEditingController(
      text: period?.description ?? '',
    );

    final savedPeriod = await showDialog<PausePeriod>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickStartDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: startDate,
                firstDate: DateTime(today.year - 5),
                lastDate: DateTime(today.year + 5),
              );
              if (picked == null) {
                return;
              }
              setDialogState(() {
                startDate = _normalizeDate(picked);
                if (endDate.isBefore(startDate)) {
                  endDate = startDate;
                }
              });
            }

            Future<void> pickEndDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: endDate.isBefore(startDate) ? startDate : endDate,
                firstDate: startDate,
                lastDate: DateTime(today.year + 5),
              );
              if (picked == null) {
                return;
              }
              setDialogState(() {
                endDate = _normalizeDate(picked);
              });
            }

            return AlertDialog(
              title: Text(period == null ? 'Add Pause' : 'Edit Pause'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Start date'),
                      subtitle: Text(_formatHumanDate(context, startDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: pickStartDate,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('End date'),
                      subtitle: Text(_formatHumanDate(context, endDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: pickEndDate,
                    ),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Reason',
                        hintText: 'Tests, travel, vacation, recovery...',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      PausePeriod(
                        startDate: startDate,
                        endDate: endDate,
                        description: descriptionController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    descriptionController.dispose();

    if (savedPeriod == null) {
      return;
    }

    final updatedPeriods = List<PausePeriod>.from(widget.habit.pausePeriods);
    if (index == null) {
      updatedPeriods.add(savedPeriod);
    } else {
      updatedPeriods[index] = savedPeriod;
    }
    updatedPeriods.sort((a, b) => a.startDate.compareTo(b.startDate));
    setState(() {
      widget.habit.pausePeriods = updatedPeriods;
    });
    await _habitBox.put(widget.habit.id, widget.habit.toMap());
    // Trigger syncAllHabitReminders to reschedule reminders taking the new pause into account
    await ReminderService.instance.syncHabitReminder(widget.habit);
    _loadLogs();
  }

  Future<void> _deletePause(int index) async {
    final period = widget.habit.pausePeriods[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Pause'),
        content: Text(
          'Delete the pause from ${_formatHumanDate(context, period.startDate)} '
          'to ${_formatHumanDate(context, period.endDate)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final updatedPeriods = List<PausePeriod>.from(widget.habit.pausePeriods)
      ..removeAt(index);
    setState(() {
      widget.habit.pausePeriods = updatedPeriods;
    });
    await _habitBox.put(widget.habit.id, widget.habit.toMap());
    await ReminderService.instance.syncHabitReminder(widget.habit);
    _loadLogs();
  }

  Widget _buildPausePeriodsSection() {
    final periods = widget.habit.pausePeriods;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Habit Pause Periods',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Pause Period',
              onPressed: () => _openPauseDialog(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (periods.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'No paused periods for this habit.',
              style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: periods.length,
            itemBuilder: (context, index) {
              final period = periods[index];
              final duration = period.endDate.difference(period.startDate).inDays + 1;
              final status = _statusLabel(period);
              final statusColor = _statusColor(status);
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                  title: Text(
                    '${_formatHumanDate(context, period.startDate)} - ${_formatHumanDate(context, period.endDate)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$duration ${duration == 1 ? 'day' : 'days'} ($status)'),
                      if (period.description.trim().isNotEmpty)
                        Text(
                          period.description,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _openPauseDialog(period: period, index: index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _deletePause(index),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
