import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/history_screen.dart';
import 'package:habit_tracker/habit_details_screen.dart';
import 'package:habit_tracker/manage_habits_screen.dart';
import 'package:habit_tracker/manage_environments_screen.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/paused_sessions_screen.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:habit_tracker/utils/execution_environment_utils.dart';
import 'package:habit_tracker/utils/habit_quality_utils.dart';
import 'package:habit_tracker/utils/habit_schedule_utils.dart'
    as schedule_utils;
import 'package:habit_tracker/utils/habit_visibility_utils.dart';
import 'package:habit_tracker/utils/pause_utils.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';

const String _priorityXpKey = 'priorityXp';
const String _priorityEmergencyUnlockKey = 'priorityEmergencyUnlockDate';
const double _priorityUnlockThreshold = 0.75;

enum _TodayMenuAction {
  exportTodayList,
  pauseTracking,
  pausedSessions,
  history,
  manageHabits,
  manageEnvironments,
}

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  static const Duration _completionMoveDelay = Duration(seconds: 1);
  late Box _habitBox;
  late Box _dailyLogBox;
  late Box _settingsBox;
  late ValueListenable<Box> _habitListenable;
  late ValueListenable<Box> _settingsListenable;
  List<Habit> _habits = [];
  Map<String, DailyLog> _dailyCompletionStatus = {};
  List<PausePeriod> _pausePeriods = [];
  List<ExecutionEnvironment> _environments = [];
  String? _selectedEnvironmentId;
  final Map<PriorityLevel, bool> _expandedPrioritySections = {};
  final Map<PriorityLevel, bool> _expandedCompletedSections = {};
  final Map<String, bool> _expandedSectionCompleted = {};
  final Map<String, Timer> _pendingCompletionTimers = {};
  int _totalXp = 0;
  DateTime? _emergencyUnlockDate;
  Timer? _visibilityRefreshTimer;

  @override
  void initState() {
    super.initState();
    _habitBox = Hive.box(HiveBoxNames.habits);
    _dailyLogBox = Hive.box(HiveBoxNames.dailyLogs);
    _settingsBox = Hive.box(HiveBoxNames.appSettings);
    _habitListenable = _habitBox.listenable();
    _settingsListenable = _settingsBox.listenable();
    _loadPriorityMetadata();
    _loadEnvironmentSettings();
    _loadHabits();
    _startVisibilityRefreshTimer();
    _habitListenable.addListener(_loadHabits);
    _settingsListenable.addListener(_loadEnvironmentSettings);
    _settingsListenable.addListener(_loadPausePeriods);
    _loadPausePeriods();
  }

  @override
  void dispose() {
    _visibilityRefreshTimer?.cancel();
    for (final timer in _pendingCompletionTimers.values) {
      timer.cancel();
    }
    _habitListenable.removeListener(_loadHabits);
    _settingsListenable.removeListener(_loadEnvironmentSettings);
    _settingsListenable.removeListener(_loadPausePeriods);
    super.dispose();
  }

  DateTime _normalizeDate(DateTime date) {
    return schedule_utils.normalizeDate(date);
  }

  void _applyRuleSnapshot(DailyLog log, Habit habit) {
    final rule = habit.currentRule;
    log.type = rule.type;
    log.frequency = rule.frequency;
    log.daysOfWeek = rule.daysOfWeek == null
        ? null
        : List<int>.from(rule.daysOfWeek!);
    log.timesPerDay = rule.timesPerDay;
  }

  void _loadEnvironmentSettings() {
    _environments = loadExecutionEnvironments(_settingsBox);
    if (_selectedEnvironmentId != null &&
        findExecutionEnvironment(_environments, _selectedEnvironmentId!) ==
            null) {
      _selectedEnvironmentId = null;
    }
    if (mounted) {
      setState(() {});
    }
  }

  List<Habit> _filterHabitsForSelectedContext(List<Habit> habits) {
    final selectedEnvironmentId = _selectedEnvironmentId;
    if (selectedEnvironmentId == null) {
      return habits;
    }
    return habits.where((habit) => habit.environmentId == selectedEnvironmentId).toList();
  }

  List<Habit> _sortHabitsForDisplay(List<Habit> habits) {
    habits.sort((a, b) {
      final importanceCompare = b.importanceScore.compareTo(a.importanceScore);
      if (importanceCompare != 0) {
        return importanceCompare;
      }
      final priorityCompare = a.priorityLevel.index.compareTo(
        b.priorityLevel.index,
      );
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return habits;
  }

  List<Habit> _buildStrategicAnchors(List<Habit> habits) {
    return _sortHabitsForDisplay(
      habits.where((habit) => habit.isStrategicAnchor).toList(),
    );
  }

  List<Habit> _buildBestForCurrentContext(List<Habit> habits) {
    final selectedEnvironmentId = _selectedEnvironmentId;
    return _sortHabitsForDisplay(
      habits.where((habit) {
        if (habit.isStrategicAnchor) {
          return false;
        }
        return selectedEnvironmentId == null
            ? true
            : habit.environmentId == selectedEnvironmentId;
      }).toList(),
    );
  }

  List<Habit> _buildDeferredForCurrentContext(List<Habit> habits) {
    final selectedEnvironmentId = _selectedEnvironmentId;
    if (selectedEnvironmentId == null) {
      return const [];
    }
    return _sortHabitsForDisplay(
      habits
          .where((habit) {
            return !habit.isStrategicAnchor &&
                habit.environmentId != selectedEnvironmentId;
          })
          .toList(),
    );
  }

  Future<void> _loadHabits() async {
    final allHabits = _habitBox.values
        .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
        .where((habit) => !habit.isArchived)
        .toList();
    for (int i = 0; i < allHabits.length; i++) {
      if (allHabits[i].sortOrder < 0) {
        allHabits[i].sortOrder = i;
      }
    }
    final today = _normalizeDate(DateTime.now());
    _habits =
        allHabits.where((habit) {
          if (_normalizeDate(habit.startDate).isAfter(today)) {
            return false;
          }
          if (habit.endDate != null &&
              _normalizeDate(habit.endDate!).isBefore(today)) {
            return false;
          }
          return schedule_utils.isScheduledDay(habit, today) &&
              isHabitVisibleNow(habit);
        }).toList()..sort((a, b) {
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

  void _loadPausePeriods() {
    _pausePeriods = loadPausePeriods(_settingsBox);
    if (mounted) {
      setState(() {});
    }
  }

  void _startVisibilityRefreshTimer() {
    if (const bool.fromEnvironment('FLUTTER_TEST') ||
        (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'))) {
      return;
    }
    _visibilityRefreshTimer?.cancel();
    _visibilityRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _loadHabits(),
    );
  }

  void _loadPriorityMetadata() {
    _totalXp = (_settingsBox.get(_priorityXpKey) as int?) ?? 0;
    final rawUnlock = _settingsBox.get(_priorityEmergencyUnlockKey) as String?;
    _emergencyUnlockDate = _parseStoredDate(rawUnlock);
  }

  Future<void> _activateEmergencyUnlock() async {
    final normalized = _normalizeDate(DateTime.now());
    await _settingsBox.put(
      _priorityEmergencyUnlockKey,
      normalized.toIso8601String(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _emergencyUnlockDate = normalized;
    });
  }

  DateTime? _parseStoredDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  bool get _isEmergencyUnlockActive {
    final stored = _emergencyUnlockDate;
    if (stored == null) {
      return false;
    }
    return _isSameDate(stored, DateTime.now());
  }

  bool get _canUseEmergencyUnlock => !_isEmergencyUnlockActive;

  Future<void> _checkDailyReset() async {
    String today = _formatDate(DateTime.now());

    // Load completion status for today
    _dailyCompletionStatus = {};
    for (var habit in _habits) {
      var logMap = _dailyLogBox.get('${habit.id}_$today');
      if (logMap != null) {
        _dailyCompletionStatus[habit.id] = DailyLog.fromMap(
          Map<String, dynamic>.from(logMap),
        );
      } else {
        final log = DailyLog(
          date: today,
          habitId: habit.id,
        );
        _applyRuleSnapshot(log, habit);
        _dailyCompletionStatus[habit.id] = log;
      }
    }
  }

  void _manageHabits() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const ManageHabitsScreen()));
  }

  Future<void> _openEnvironmentManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ManageEnvironmentsScreen()),
    );
    if (!mounted) {
      return;
    }
    _loadEnvironmentSettings();
    await _loadHabits();
  }

  Future<void> _openTodayExportMenu() async {
    final action = await showModalBottomSheet<_TodayExportAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy today list'),
                subtitle: const Text('Paste it into Notes or chat'),
                onTap: () => Navigator.of(sheetContext).pop(
                  _TodayExportAction.copy,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Share today list'),
                subtitle: const Text('Send it to Notes, Keep, or email'),
                onTap: () => Navigator.of(sheetContext).pop(
                  _TodayExportAction.share,
                ),
              ),
            ],
          ),
        );
      },
    );

    switch (action) {
      case _TodayExportAction.copy:
        await _copyTodayList();
        break;
      case _TodayExportAction.share:
        await _shareTodayList();
        break;
      case null:
        break;
    }
  }

  String _formatChecklistDate(DateTime date) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _buildTodayChecklistText() {
    final today = _normalizeDate(DateTime.now());
    final filteredHabits = _filterHabitsForSelectedContext(_habits);
    final groups = _buildPriorityGroups(filteredHabits);
    final buffer = StringBuffer()
      ..writeln("Today's Habits - ${_formatChecklistDate(today)}");

    final selectedEnvironmentId = _selectedEnvironmentId;
    if (selectedEnvironmentId != null) {
      buffer.writeln(
        'Context: ${environmentDisplayName(_environments, selectedEnvironmentId)}',
      );
    }

    if (_isTodayPaused()) {
      buffer.writeln('Tracking paused today.');
    }

    for (final level in PriorityLevel.values) {
      final habits = groups[level] ?? const <Habit>[];
      if (habits.isEmpty) {
        continue;
      }
      buffer
        ..writeln()
        ..writeln(level.displayName.toUpperCase());
      for (final habit in habits) {
        final log = _dailyCompletionStatus[habit.id];
        final isCompleted = _isHabitShownAsCompletedToday(habit);
        final marker = isCompleted ? '[x]' : '[ ]';
        final countSuffix = habit.type == HabitType.counted &&
                habit.timesPerDay != null
            ? ' (${log?.count ?? 0}/${habit.timesPerDay})'
            : '';
        buffer.writeln('$marker ${habit.name}$countSuffix');
      }
    }

    return buffer.toString().trimRight();
  }

  Future<void> _copyTodayList() async {
    await Clipboard.setData(
      ClipboardData(text: _buildTodayChecklistText()),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Today list copied to clipboard.')),
    );
  }

  Future<void> _shareTodayList() async {
    await SharePlus.instance.share(
      ShareParams(
        text: _buildTodayChecklistText(),
        title: "Today's habits",
        subject: "Today's habits",
      ),
    );
  }

  void _openHistory() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const HistoryScreen()));
  }

  void _openPausedSessions() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const PausedSessionsScreen()),
    );
  }

  Future<void> _toggleHabitCompletion(Habit habit, bool? newValue) async {
    if (_isTodayPaused()) {
      return;
    }
    final nextValue = newValue ?? false;
    String today = _formatDate(DateTime.now());
    DailyLog log =
        _dailyCompletionStatus[habit.id] ??
        DailyLog(date: today, habitId: habit.id);
    _applyRuleSnapshot(log, habit);
    final wasCompleted = log.completed;

    if (!wasCompleted && nextValue) {
      final quality = await _promptForQuality(
        habit,
        initialQuality: log.quality,
      );
      if (!mounted || quality == null) {
        return;
      }
      log.quality = quality;
    } else if (!nextValue) {
      log.quality = null;
    }

    _pendingCompletionTimers.remove(habit.id)?.cancel();
    log.completed = nextValue;

    setState(() {
      _dailyCompletionStatus[habit.id] = log;
    });

    if (!wasCompleted && nextValue) {
      _pendingCompletionTimers[habit.id] = Timer(
        _completionMoveDelay,
        () async {
          _pendingCompletionTimers.remove(habit.id);
          _applyRuleSnapshot(log, habit);
          await _dailyLogBox.put('${habit.id}_$today', log.toMap());
          final updatedXp = await _tryAwardXpForCompletion(
            habit,
            wasCompleted,
            log.completed,
          );
          if (!mounted) {
            return;
          }
          setState(() {
            if (updatedXp != null) {
              _totalXp = updatedXp;
            }
          });
        },
      );
      return;
    }

    await _dailyLogBox.put('${habit.id}_$today', log.toMap());
    final updatedXp = await _tryAwardXpForCompletion(
      habit,
      wasCompleted,
      log.completed,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      if (updatedXp != null) {
        _totalXp = updatedXp;
      }
    });
  }

  Future<void> _incrementHabitCount(Habit habit) async {
    if (_isTodayPaused()) {
      return;
    }
    String today = _formatDate(DateTime.now());
    DailyLog log =
        _dailyCompletionStatus[habit.id] ??
        DailyLog(date: today, habitId: habit.id);
    _applyRuleSnapshot(log, habit);
    log.count = (log.count ?? 0) + 1;
    final wasCompleted = log.completed;
    if (habit.timesPerDay != null && log.count! >= habit.timesPerDay!) {
      if (!wasCompleted) {
        final quality = await _promptForQuality(
          habit,
          initialQuality: log.quality,
        );
        if (!mounted || quality == null) {
          log.count = log.count! - 1;
          return;
        }
        log.quality = quality;
      }
      log.completed = true;
    }
    await _dailyLogBox.put('${habit.id}_$today', log.toMap());
    final updatedXp = await _tryAwardXpForCompletion(
      habit,
      wasCompleted,
      log.completed,
    );
    setState(() {
      _dailyCompletionStatus[habit.id] = log;
      if (updatedXp != null) {
        _totalXp = updatedXp;
      }
    });
  }

  Future<void> _decrementHabitCount(Habit habit) async {
    if (_isTodayPaused()) {
      return;
    }
    String today = _formatDate(DateTime.now());
    DailyLog log =
        _dailyCompletionStatus[habit.id] ??
        DailyLog(date: today, habitId: habit.id);
    _applyRuleSnapshot(log, habit);
    log.count = (log.count ?? 0) > 0 ? (log.count! - 1) : 0;
    final wasCompleted = log.completed;
    if (habit.timesPerDay != null && log.count! < habit.timesPerDay!) {
      log.completed = false;
      log.quality = null;
    }
    await _dailyLogBox.put('${habit.id}_$today', log.toMap());
    final updatedXp = await _tryAwardXpForCompletion(
      habit,
      wasCompleted,
      log.completed,
    );
    setState(() {
      _dailyCompletionStatus[habit.id] = log;
      if (updatedXp != null) {
        _totalXp = updatedXp;
      }
    });
  }

  Future<int?> _tryAwardXpForCompletion(
    Habit habit,
    bool wasCompleted,
    bool isCompleted,
  ) async {
    if (wasCompleted || !isCompleted) {
      return null;
    }
    final reward = habit.priorityLevel.xpReward;
    if (reward <= 0) {
      return null;
    }
    final nextTotal = _totalXp + reward;
    await _settingsBox.put(_priorityXpKey, nextTotal);
    return nextTotal;
  }

  Future<int?> _promptForQuality(Habit habit, {int? initialQuality}) {
    return showDialog<int>(
      context: context,
      builder: (_) => _QualityRatingDialog(
        habitName: habit.name,
        initialQuality: initialQuality,
      ),
    );
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${habit.name} timer completed.')));
  }

  String _formatDate(DateTime date) {
    return schedule_utils.formatDate(date);
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return schedule_utils.isSameDate(a, b);
  }

  bool _isHabitCompletedOnDate(Habit habit, DateTime date) {
    final dateString = _formatDate(_normalizeDate(date));
    final logMap = _dailyLogBox.get('${habit.id}_$dateString');
    if (logMap == null) {
      return false;
    }
    final log = DailyLog.fromMap(Map<String, dynamic>.from(logMap));
    return log.completed;
  }

  List<DailyLog> _getCompletedLogsForRange(
    Habit habit,
    DateTime endDate, {
    required int days,
  }) {
    final logs = <DailyLog>[];
    final normalizedEnd = _normalizeDate(endDate);
    final startDate = normalizedEnd.subtract(Duration(days: days - 1));
    DateTime date = startDate;
    while (!date.isAfter(normalizedEnd)) {
      if (_isPaused(date) || !schedule_utils.isScheduledDay(habit, date)) {
        date = date.add(const Duration(days: 1));
        continue;
      }
      final dateString = _formatDate(date);
      final logMap = _dailyLogBox.get('${habit.id}_$dateString');
      if (logMap != null) {
        final log = DailyLog.fromMap(Map<String, dynamic>.from(logMap));
        if (log.completed) {
          logs.add(log);
        }
      }
      date = date.add(const Duration(days: 1));
    }
    return logs;
  }

  double? _getAverageQuality(Habit habit) {
    final logs = _dailyLogBox.values
        .map(
          (entry) => DailyLog.fromMap(Map<String, dynamic>.from(entry as Map)),
        )
        .where((log) => log.habitId == habit.id);
    return averageQuality(logs);
  }

  HabitQualityTrend _getQualityTrend(Habit habit) {
    final endDate = _getStatsEndDate(habit);
    if (endDate == null) {
      return HabitQualityTrend.insufficientData;
    }
    final recentLogs = _getCompletedLogsForRange(habit, endDate, days: 14);
    final previousLogs = _getCompletedLogsForRange(
      habit,
      endDate.subtract(const Duration(days: 14)),
      days: 14,
    );
    return calculateQualityTrend(
      recentLogs: recentLogs,
      previousLogs: previousLogs,
    );
  }

  DateTime? _getStatsEndDate(Habit habit) {
    final today = _normalizeDate(DateTime.now());
    final normalizedStart = _normalizeDate(habit.startDate);
    final normalizedEndDate = habit.endDate != null
        ? _normalizeDate(habit.endDate!)
        : null;
    final statsEnd =
        normalizedEndDate != null && normalizedEndDate.isBefore(today)
        ? normalizedEndDate
        : today;
    final shouldExcludeToday =
        _isSameDate(statsEnd, today) &&
        !_isPaused(today) &&
        schedule_utils.isScheduledDay(habit, today) &&
        !_isHabitCompletedOnDate(habit, today);
    final effectiveStatsEnd = shouldExcludeToday
        ? statsEnd.subtract(const Duration(days: 1))
        : statsEnd;
    if (effectiveStatsEnd.isBefore(normalizedStart)) {
      return null;
    }
    return effectiveStatsEnd;
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
    final statsEnd = _getStatsEndDate(habit);
    if (statsEnd == null) {
      return 0;
    }
    int streak = 0;
    final normalizedStart = _normalizeDate(habit.startDate);
    DateTime date = statsEnd;
    while (!date.isBefore(normalizedStart)) {
      if (_isPaused(date)) {
        date = date.subtract(const Duration(days: 1));
        continue;
      }
      if (!schedule_utils.isScheduledDay(habit, date)) {
        date = date.subtract(const Duration(days: 1));
        continue;
      }
      if (_isHabitCompletedOnDate(habit, date)) {
        streak++;
        date = date.subtract(const Duration(days: 1));
        continue;
      }
      break;
    }
    return streak;
  }

  double _getSuccessRate(Habit habit) {
    final start = _normalizeDate(habit.startDate);
    final end = _getStatsEndDate(habit);
    if (end == null) {
      return 0;
    }
    int completedScheduledDays = 0;
    int totalScheduledDays = 0;
    DateTime date = start;
    while (!date.isAfter(end)) {
      if (_isPaused(date)) {
        date = date.add(const Duration(days: 1));
        continue;
      }
      if (schedule_utils.isScheduledDay(habit, date)) {
        totalScheduledDays++;
        if (_isHabitCompletedOnDate(habit, date)) {
          completedScheduledDays++;
        }
      }
      date = date.add(const Duration(days: 1));
    }
    return totalScheduledDays > 0
        ? (completedScheduledDays / totalScheduledDays) * 100
        : 0;
  }

  bool _isPaused(DateTime date) => isPausedOnDate(_pausePeriods, date);

  bool _isTodayPaused() => _isPaused(_normalizeDate(DateTime.now()));

  PausePeriod? _getActivePausePeriod() =>
      getActivePausePeriod(_pausePeriods, today: DateTime.now());

  PausePeriod? _getNextPausePeriod() {
    final today = _normalizeDate(DateTime.now());
    for (final period in _pausePeriods) {
      if (_normalizeDate(period.startDate).isAfter(today)) {
        return period;
      }
    }
    return null;
  }

  String _formatHumanDate(BuildContext context, DateTime date) {
    return MaterialLocalizations.of(
      context,
    ).formatMediumDate(_normalizeDate(date));
  }

  Future<void> _openPauseDialog() async {
    final today = _normalizeDate(DateTime.now());
    final initialStart = today;
    final initialEnd = _getActivePausePeriod()?.endDate ?? today;
    DateTime startDate = initialStart;
    DateTime endDate = initialEnd;
    final descriptionController = TextEditingController();

    final newPause = await showDialog<PausePeriod>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickStartDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: startDate,
                firstDate: DateTime(today.year - 1),
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
              scrollable: true,
              title: const Text('Pause Tracking'),
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
                        hintText: 'Exams, travel, vacation, recovery...',
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
                  child: const Text('Pause'),
                ),
              ],
            );
          },
        );
      },
    );
    descriptionController.dispose();

    if (!mounted || newPause == null) {
      return;
    }

    final updatedPeriods = List<PausePeriod>.from(_pausePeriods)
      ..add(newPause)
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    await savePausePeriods(_settingsBox, updatedPeriods);
    await ReminderService.instance.syncAllHabitReminders(_habitBox);
    await _loadHabits();

    if (!mounted) {
      return;
    }

    final activePause = _getActivePausePeriod();
    if (activePause != null) {
      final pauseReason = activePause.description.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pauseReason.isEmpty
                ? 'Tracking paused until ${_formatHumanDate(context, activePause.endDate)}.'
                : 'Tracking paused until ${_formatHumanDate(context, activePause.endDate)}: $pauseReason',
          ),
        ),
      );
    }
  }

  Future<void> _clearActivePause() async {
    final activePause = _getActivePausePeriod();
    if (activePause == null) {
      return;
    }
    final updatedPeriods = _pausePeriods.where((period) {
      return period.startDate != activePause.startDate ||
          period.endDate != activePause.endDate;
    }).toList();
    await savePausePeriods(_settingsBox, updatedPeriods);
    await ReminderService.instance.syncAllHabitReminders(_habitBox);
    await _loadHabits();
  }

  @override
  Widget build(BuildContext context) {
    _keepLegacyPriorityUiReferences();
    final isTodayPaused = _isTodayPaused();
    final activePause = _getActivePausePeriod();
    final nextPause = activePause ?? _getNextPausePeriod();
    final visibleHabits = List<Habit>.from(_habits);
    final filteredHabits = _filterHabitsForSelectedContext(visibleHabits);
    final priorityGroups = _buildPriorityGroups(filteredHabits);
    final priorityStats = _buildPriorityStats(priorityGroups);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          PopupMenuButton<_TodayMenuAction>(
            tooltip: 'More',
            onSelected: (action) {
              switch (action) {
                case _TodayMenuAction.exportTodayList:
                  _openTodayExportMenu();
                  break;
                case _TodayMenuAction.pauseTracking:
                  _openPauseDialog();
                  break;
                case _TodayMenuAction.pausedSessions:
                  _openPausedSessions();
                  break;
                case _TodayMenuAction.history:
                  _openHistory();
                  break;
                case _TodayMenuAction.manageHabits:
                  _manageHabits();
                  break;
                case _TodayMenuAction.manageEnvironments:
                  _openEnvironmentManager();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _TodayMenuAction.exportTodayList,
                child: Row(
                  children: [
                    const Icon(Icons.ios_share, size: 20),
                    const SizedBox(width: 12),
                    const Text('Export / share today list'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _TodayMenuAction.pauseTracking,
                child: Row(
                  children: [
                    Icon(
                      isTodayPaused
                          ? Icons.pause_circle_filled
                          : Icons.pause_circle_outline,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(isTodayPaused ? 'Resume tracking' : 'Pause tracking'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: _TodayMenuAction.pausedSessions,
                child: Row(
                  children: [
                    Icon(Icons.event_busy, size: 20),
                    SizedBox(width: 12),
                    Text('Paused sessions'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: _TodayMenuAction.history,
                child: Row(
                  children: [
                    Icon(Icons.history, size: 20),
                    SizedBox(width: 12),
                    Text('History'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: _TodayMenuAction.manageHabits,
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 20),
                    SizedBox(width: 12),
                    Text('Manage habits'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: _TodayMenuAction.manageEnvironments,
                child: Row(
                  children: [
                    Icon(Icons.public, size: 20),
                    SizedBox(width: 12),
                    Text('Manage environments'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (nextPause != null)
            _buildPauseBanner(context, isTodayPaused, nextPause),
          const SizedBox(height: 16),
          _buildExecutionContextFilter(),
          const SizedBox(height: 8),
          _buildEnvironmentSummaryCard(
            priorityStats: priorityStats,
          ),
          const SizedBox(height: 8),
          _buildXpCard(),
          const SizedBox(height: 16),
          for (final level in PriorityLevel.values) ...[
            _buildPrioritySection(
              level: level,
              habits: priorityGroups[level] ?? const <Habit>[],
              stats: priorityStats[level] ?? const _PriorityLevelStats(0, 0),
              isTodayPaused: isTodayPaused,
            ),
            if (level != PriorityLevel.values.last) const SizedBox(height: 12),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildEnvironmentSummaryCard({
    required Map<PriorityLevel, _PriorityLevelStats> priorityStats,
  }) {
    final selectedEnvironmentId = _selectedEnvironmentId;
    final contextLabel = selectedEnvironmentId == null
        ? 'All environments'
        : environmentDisplayName(_environments, selectedEnvironmentId);
    final coreStats =
        priorityStats[PriorityLevel.core] ?? const _PriorityLevelStats(0, 0);
    final importantStats = priorityStats[PriorityLevel.secondary] ??
        const _PriorityLevelStats(0, 0);
    final optionalStats = priorityStats[PriorityLevel.optional] ??
        const _PriorityLevelStats(0, 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Execution overview',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text('Current environment: $contextLabel'),
              const SizedBox(height: 10),
              Text('Core: ${coreStats.total}'),
              Text('Important: ${importantStats.total}'),
              Text('Optional: ${optionalStats.total}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrioritySection({
    required PriorityLevel level,
    required List<Habit> habits,
    required _PriorityLevelStats stats,
    required bool isTodayPaused,
  }) {
    final isExpanded = _expandedPrioritySections[level] ?? true;
    final activeHabits = habits
        .where((habit) => !_isHabitShownAsCompletedToday(habit))
        .toList();
    final completedHabits = habits
        .where(_isHabitShownAsCompletedToday)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () {
            setState(() {
              _expandedPrioritySections[level] =
                  !(_expandedPrioritySections[level] ?? true);
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: level.accentColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        level.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '${stats.completed}/${stats.total}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _prioritySectionSubtitle(level),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isExpanded) ...[
                  const SizedBox(height: 12),
                  if (habits.isEmpty)
                    Text('No ${level.displayName} habits are scheduled for today.')
                  else ...[
                    ...activeHabits.map((habit) {
                      final log =
                          _dailyCompletionStatus[habit.id] ??
                          DailyLog(
                            date: _formatDate(DateTime.now()),
                            habitId: habit.id,
                          );
                      return _buildHabitCard(
                        habit,
                        log,
                        isTodayPaused,
                        isCompleted: false,
                      );
                    }),
                    if (activeHabits.isEmpty && completedHabits.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'All ${level.displayName} habits completed.',
                          style: TextStyle(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (completedHabits.isNotEmpty) ...[
                      _buildSectionCompletedHeader(
                        level: level,
                        completedCount: completedHabits.length,
                      ),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 200),
                        crossFadeState:
                            (_expandedCompletedSections[level] ?? false)
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                        firstChild: Column(
                          children: completedHabits.map((habit) {
                            final log =
                                _dailyCompletionStatus[habit.id] ??
                                DailyLog(
                                  date: _formatDate(DateTime.now()),
                                  habitId: habit.id,
                                );
                            return _buildHabitCard(
                              habit,
                              log,
                              isTodayPaused,
                              isCompleted: true,
                            );
                          }).toList(),
                        ),
                        secondChild: const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _prioritySectionSubtitle(PriorityLevel level) {
    switch (level) {
      case PriorityLevel.core:
        return 'Most important work for today.';
      case PriorityLevel.secondary:
        return 'Important work that still matters now.';
      case PriorityLevel.optional:
        return 'Lower-priority work you can do if time allows.';
    }
  }

  Widget _buildExecutionContextFilter() {
    final selectedEnvironmentId = _selectedEnvironmentId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current environment',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text('Choose the environment you are actually in.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: selectedEnvironmentId == null,
                    onSelected: (_) {
                      setState(() {
                        _selectedEnvironmentId = null;
                      });
                    },
                  ),
                  ..._environments.map((environment) {
                    return ChoiceChip(
                      avatar: Icon(environment.icon, size: 18),
                      label: Text(environment.name),
                      selected: selectedEnvironmentId == environment.id,
                      onSelected: (_) {
                        setState(() {
                          _selectedEnvironmentId = environment.id;
                        });
                      },
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPauseBanner(
    BuildContext context,
    bool isTodayPaused,
    PausePeriod nextPause,
  ) {
    final description = nextPause.description.trim();
    final suffix = description.isEmpty ? '' : ' • $description';
    final message = isTodayPaused
        ? 'Tracking paused until ${_formatHumanDate(context, nextPause.endDate)}$suffix'
        : 'Upcoming pause: ${_formatHumanDate(context, nextPause.startDate)} to ${_formatHumanDate(context, nextPause.endDate)}$suffix';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.pause_circle, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          if (isTodayPaused)
            TextButton(
              onPressed: _clearActivePause,
              child: const Text('Resume'),
            ),
        ],
      ),
    );
  }

  Widget _buildFocusCard(_PriorityLevelStats coreStats) {
    final focusText = coreStats.total == 0
        ? 'No core habits scheduled for today.'
        : 'Core habits: ${coreStats.completed}/${coreStats.total} done.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.track_changes, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  focusText,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildUnlockAnnouncements(
    Map<PriorityLevel, _PriorityLevelStats> stats,
  ) {
    return const <Widget>[];
  }

  Widget _buildUnlockBanner(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: Colors.green.shade800,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildXpCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.auto_graph, color: Colors.amber),
              const SizedBox(width: 12),
              const Text(
                'XP points',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '$_totalXp XP',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _PriorityLevelStats _buildSectionStats(List<Habit> habits) {
    final completed = habits.where((habit) {
      return _dailyCompletionStatus[habit.id]?.completed == true;
    }).length;
    return _PriorityLevelStats(habits.length, completed);
  }

  Widget _buildTaskSection({
    required String title,
    required String subtitle,
    required List<Habit> habits,
    required _PriorityLevelStats stats,
    required bool isTodayPaused,
    required String emptyMessage,
    required String sectionKey,
  }) {
    final activeHabits = habits
        .where((habit) => !_isHabitShownAsCompletedToday(habit))
        .toList();
    final completedHabits = habits
        .where(_isHabitShownAsCompletedToday)
        .toList();
    final completedExpanded = _expandedSectionCompleted[sectionKey] ?? false;

    return Column(
      children: [
        _buildSectionHeader(
          title: title,
          subtitle: subtitle,
          stats: stats,
          sectionKey: sectionKey,
        ),
        const SizedBox(height: 8),
        if (habits.isEmpty)
          _buildEmptySectionCard(emptyMessage)
        else ...[
          ...activeHabits.map((habit) {
            final log =
                _dailyCompletionStatus[habit.id] ??
                DailyLog(date: _formatDate(DateTime.now()), habitId: habit.id);
            return _buildHabitCard(habit, log, isTodayPaused, isCompleted: false);
          }),
          if (activeHabits.isEmpty && completedHabits.isNotEmpty)
            _buildSectionCompleteCard(title),
          if (completedHabits.isNotEmpty) ...[
            _buildSectionCompletedHeader(
              title: title,
              completedCount: completedHabits.length,
              sectionKey: sectionKey,
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: completedExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Column(
                children: completedHabits.map((habit) {
                  final log =
                      _dailyCompletionStatus[habit.id] ??
                      DailyLog(
                        date: _formatDate(DateTime.now()),
                        habitId: habit.id,
                      );
                  return _buildHabitCard(
                    habit,
                    log,
                    isTodayPaused,
                    isCompleted: true,
                  );
                }).toList(),
              ),
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required _PriorityLevelStats stats,
    required String sectionKey,
  }) {
    final isExpanded = _expandedSectionCompleted[sectionKey] ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: stats.completed > 0
              ? () => _toggleSectionCompletion(sectionKey)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${stats.completed}/${stats.total}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (stats.completed > 0) ...[
                      const SizedBox(width: 8),
                      Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCompletedHeader({
    required String title,
    required int completedCount,
    required String sectionKey,
  }) {
    final isExpanded = _expandedSectionCompleted[sectionKey] ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleSectionCompletion(sectionKey),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$title completed ($completedCount)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySectionCard(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(message),
        ),
      ),
    );
  }

  Widget _buildSectionCompleteCard(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '$title complete for today.',
            style: TextStyle(
              color: Colors.green.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _toggleSectionCompletion(String sectionKey) {
    setState(() {
      _expandedSectionCompleted[sectionKey] =
          !(_expandedSectionCompleted[sectionKey] ?? false);
    });
  }

  void _keepLegacyPriorityUiReferences() {
    if (DateTime.now().millisecondsSinceEpoch == -1) {
      final dummyHabits = <Habit>[];
      final dummyStats = _buildPriorityStats(_buildPriorityGroups(dummyHabits));
      _buildFocusCard(const _PriorityLevelStats(0, 0));
      _buildUnlockAnnouncements(dummyStats);
      _buildPriorityLevelWidgets(
        level: PriorityLevel.core,
        habits: dummyHabits,
        stats: const _PriorityLevelStats(0, 0),
        unlocked: true,
        isTodayPaused: false,
        statsMap: dummyStats,
      );
    }
  }

  Map<PriorityLevel, List<Habit>> _buildPriorityGroups(List<Habit> habits) {
    final groups = <PriorityLevel, List<Habit>>{
      for (final level in PriorityLevel.values) level: [],
    };
    for (final habit in habits) {
      groups[habit.priorityLevel]!.add(habit);
    }
    for (final list in groups.values) {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return groups;
  }

  Map<PriorityLevel, _PriorityLevelStats> _buildPriorityStats(
    Map<PriorityLevel, List<Habit>> groups,
  ) {
    final stats = <PriorityLevel, _PriorityLevelStats>{};
    groups.forEach((level, habits) {
      final completed = habits.where((habit) {
        return _dailyCompletionStatus[habit.id]?.completed == true;
      }).length;
      stats[level] = _PriorityLevelStats(habits.length, completed);
    });
    return stats;
  }

  bool _isLevelUnlocked(
    PriorityLevel level,
    Map<PriorityLevel, _PriorityLevelStats> stats,
  ) {
    if (level == PriorityLevel.core || level == PriorityLevel.secondary) {
      return true;
    }
    if (_isEmergencyUnlockActive) {
      return true;
    }
    final previousLevel = PriorityLevel.values[level.index - 1];
    final previousStats = stats[previousLevel]!;
    if (previousStats.total == 0) {
      return true;
    }
    return previousStats.completed / previousStats.total >=
        _priorityUnlockThreshold;
  }

  bool _isHabitCompletedToday(Habit habit) {
    return _dailyCompletionStatus[habit.id]?.completed == true;
  }

  bool _isHabitPendingCompletion(Habit habit) {
    return _pendingCompletionTimers.containsKey(habit.id);
  }

  bool _isHabitShownAsCompletedToday(Habit habit) {
    return _isHabitCompletedToday(habit) && !_isHabitPendingCompletion(habit);
  }

  void _toggleCompletedSection(PriorityLevel level) {
    setState(() {
      _expandedCompletedSections[level] =
          !(_expandedCompletedSections[level] ?? false);
    });
  }

  List<Widget> _buildPriorityLevelWidgets({
    required PriorityLevel level,
    required List<Habit> habits,
    required _PriorityLevelStats stats,
    required bool unlocked,
    required bool isTodayPaused,
    required Map<PriorityLevel, _PriorityLevelStats> statsMap,
  }) {
    final widgets = <Widget>[];
    widgets.add(_buildLevelHeader(level, stats, unlocked));
    widgets.add(const SizedBox(height: 8));
    if (!unlocked) {
      final previousLevel = PriorityLevel.values[level.index - 1];
      widgets.add(
        _buildLockedSection(level, previousLevel, statsMap[previousLevel]!),
      );
    } else if (habits.isEmpty) {
      widgets.add(_buildEmptyLevelCard(level));
    } else {
      final activeHabits = habits.where(
        (habit) => !_isHabitShownAsCompletedToday(habit),
      );
      final completedHabits = habits
          .where(_isHabitShownAsCompletedToday)
          .toList();

      for (final habit in activeHabits) {
        final log =
            _dailyCompletionStatus[habit.id] ??
            DailyLog(date: _formatDate(DateTime.now()), habitId: habit.id);
        widgets.add(
          _buildHabitCard(habit, log, isTodayPaused, isCompleted: false),
        );
      }

      if (activeHabits.isEmpty && completedHabits.isNotEmpty) {
        widgets.add(_buildAllDoneCard(level));
      }

      if (completedHabits.isNotEmpty) {
        widgets.add(
          _buildCompletedSectionHeader(
            level: level,
            completedCount: completedHabits.length,
          ),
        );
        widgets.add(
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: (_expandedCompletedSections[level] ?? false)
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              children: completedHabits.map((habit) {
                final log =
                    _dailyCompletionStatus[habit.id] ??
                    DailyLog(
                      date: _formatDate(DateTime.now()),
                      habitId: habit.id,
                    );
                return _buildHabitCard(
                  habit,
                  log,
                  isTodayPaused,
                  isCompleted: true,
                );
              }).toList(),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildLevelHeader(
    PriorityLevel level,
    _PriorityLevelStats stats,
    bool unlocked,
  ) {
    final statusText = '${stats.completed}/${stats.total} done';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: level.accentColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                level.displayName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Row(
            children: [
              if (!unlocked) ...[
                const Icon(Icons.lock, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
              ],
              Text(
                statusText,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: level.accentColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLockedSection(
    PriorityLevel level,
    PriorityLevel previousLevel,
    _PriorityLevelStats previousStats,
  ) {
    final requirement = math.min(
      previousStats.total,
      (previousStats.total * _priorityUnlockThreshold).ceil(),
    );
    final progressPercent = previousStats.total == 0
        ? '0'
        : ((previousStats.completed / previousStats.total) * 100)
              .clamp(0, 100)
              .toStringAsFixed(0);
    final message = previousStats.total == 0
        ? 'Add ${previousLevel.displayName} habits to unlock ${level.displayName} habits.'
        : 'Complete $requirement ${previousLevel.displayName} habits ($progressPercent% done) to unlock this level.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 8),
              if (level == PriorityLevel.secondary) ...[
                _canUseEmergencyUnlock
                    ? TextButton(
                        onPressed: _activateEmergencyUnlock,
                        child: const Text('Emergency unlock (once per day)'),
                      )
                    : Text(
                        'Emergency unlock used today.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyLevelCard(PriorityLevel level) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No ${level.displayName} habits are scheduled for today.'),
        ),
      ),
    );
  }

  Widget _buildAllDoneCard(PriorityLevel level) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'All ${level.displayName} habits completed.',
            style: TextStyle(
              color: Colors.green.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedSectionHeader({
    required PriorityLevel level,
    required int completedCount,
  }) {
    final isExpanded = _expandedCompletedSections[level] ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleCompletedSection(level),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Completed ($completedCount)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHabitCard(
    Habit habit,
    DailyLog log,
    bool isTodayPaused, {
    bool isCompleted = false,
  }) {
    final averageQualityValue = _getAverageQuality(habit);
    final qualityTrend = _getQualityTrend(habit);
    final streak = _getStreak(habit);
    final successRate = _getSuccessRate(habit);
    final tertiaryDetails = <String>[
      if (averageQualityValue != null)
        'Avg ${averageQualityValue.toStringAsFixed(1)} / 4',
      if (qualityTrend != HabitQualityTrend.insufficientData)
        qualityTrendLabel(qualityTrend),
    ];

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => HabitDetailsScreen(habit: habit),
          ),
        );
      },
      child: Opacity(
        opacity: isTodayPaused ? 0.65 : (isCompleted ? 0.6 : 1),
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 8, height: 56, color: habit.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              habit.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                decoration: isCompleted
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                            ),
                          ),
                          if (habit.isImportant) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                      if (habit.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          habit.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildMetricChip('Streak $streak'),
                          _buildMetricChip(
                            'Success ${successRate.toStringAsFixed(0)}%',
                          ),
                        ],
                      ),
                      if (tertiaryDetails.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          tertiaryDetails.join(' | '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (log.completed && log.quality != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Today: ${qualityLabel(log.quality!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (isTodayPaused) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Tracking paused today',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (habit.useTimeVisibility &&
                          habit.visibleAfterHour != null &&
                          habit.visibleAfterMinute != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Visible after ${formatHabitVisibleAfter(habit, context)!}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if ((habit.timerMinutes ?? 0) > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatTimerLabel(habit.timerMinutes!),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: isTodayPaused
                                  ? null
                                  : () => _startHabitTimer(habit),
                              child: const Text('Start Timer'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (habit.type == HabitType.binary)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Checkbox(
                      value: log.completed,
                      onChanged: isTodayPaused
                          ? null
                          : (value) {
                              _toggleHabitCompletion(habit, value);
                            },
                    ),
                  ),
                if (habit.type == HabitType.counted)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: isTodayPaused
                              ? null
                              : () => _decrementHabitCount(habit),
                        ),
                        Text('${log.count ?? 0} / ${habit.timesPerDay ?? ''}'),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: isTodayPaused
                              ? null
                              : () => _incrementHabitCount(habit),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

enum _TodayExportAction { copy, share }

class _QualityRatingDialog extends StatelessWidget {
  final String habitName;
  final int? initialQuality;

  const _QualityRatingDialog({required this.habitName, this.initialQuality});

  @override
  Widget build(BuildContext context) {
    final options = <int>[1, 2, 3, 4];
    return AlertDialog(
      title: const Text('Completed!'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(habitName, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const Text('How well did you do this?'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((quality) {
              final selected = quality == initialQuality;
              return ChoiceChip(
                label: Text(qualityLabel(quality)),
                selected: selected,
                onSelected: (_) => Navigator.of(context).pop(quality),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _PriorityLevelStats {
  final int total;
  final int completed;

  const _PriorityLevelStats(this.total, this.completed);

  double get completionRate => total == 0 ? 1 : completed / total;
}

class _HabitTimerDialog extends StatefulWidget {
  final String habitName;
  final Duration duration;

  const _HabitTimerDialog({required this.habitName, required this.duration});

  @override
  State<_HabitTimerDialog> createState() => _HabitTimerDialogState();
}

class _HabitTimerDialogState extends State<_HabitTimerDialog>
    with WidgetsBindingObserver {
  Timer? _ticker;
  late int _remainingSeconds;
  late int _initialSeconds;
  bool _running = false;
  DateTime? _runningUntil;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialSeconds = widget.duration.inSeconds;
    _remainingSeconds = _initialSeconds;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) {
      return;
    }
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _syncRemainingFromClock();
    }
  }

  void _toggleRunState() {
    if (_running) {
      _pauseTimer();
      return;
    }
    _startTimer();
  }

  void _startTimer() {
    _runningUntil = DateTime.now().add(Duration(seconds: _remainingSeconds));
    setState(() {
      _running = true;
    });
    _startTicker();
  }

  void _pauseTimer() {
    _syncRemainingFromClock();
    _ticker?.cancel();
    _ticker = null;
    _runningUntil = null;
    if (mounted) {
      setState(() {
        _running = false;
      });
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_running) {
        timer.cancel();
        return;
      }
      _syncRemainingFromClock();
    });
  }

  void _syncRemainingFromClock() {
    final target = _runningUntil;
    if (target == null) {
      return;
    }
    final secondsLeft = target.difference(DateTime.now()).inSeconds;
    if (secondsLeft <= 0) {
      _ticker?.cancel();
      _ticker = null;
      _runningUntil = null;
      setState(() {
        _remainingSeconds = 0;
        _running = false;
      });
      Navigator.of(context).pop(true);
      return;
    }
    if (_remainingSeconds != secondsLeft && mounted) {
      setState(() {
        _remainingSeconds = secondsLeft;
      });
    }
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    _runningUntil = null;
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
      title: Text(
        '${widget.habitName} Timer',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
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
              TextButton(onPressed: _reset, child: const Text('Reset')),
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
