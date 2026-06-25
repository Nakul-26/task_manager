import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive/hive.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/utils/pause_utils.dart';
import 'package:habit_tracker/utils/habit_schedule_utils.dart'
    as schedule_utils;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();

  static const int _notificationsPerHabit = 100;
  static const int _oddEvenSchedules = 60;
  static const String _channelId = 'habit_reminders';
  static final bool _isTestEnvironment =
      const bool.fromEnvironment('FLUTTER_TEST') ||
      Platform.environment.containsKey('FLUTTER_TEST');

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_isTestEnvironment) {
      _initialized = true;
      return;
    }
    if (_initialized) {
      return;
    }

    tz.initializeTimeZones();
    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone()
          .timeout(const Duration(seconds: 2));
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      // Fallback to default timezone location if device timezone lookup fails or times out.
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);

    final androidImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.requestNotificationsPermission();

    final iosImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    _initialized = true;
  }

  Future<void> syncAllHabitReminders(Box<dynamic> habitBox) async {
    if (_isTestEnvironment) {
      return;
    }
    await initialize();
    final habits = habitBox.values
        .map((value) => Habit.fromMap(Map<String, dynamic>.from(value)))
        .toList();

    for (final habit in habits) {
      await syncHabitReminder(habit);
    }
  }

  Future<void> syncHabitReminder(Habit habit) async {
    if (_isTestEnvironment) {
      return;
    }
    await initialize();
    await cancelHabitReminders(habit.id);

    if (!habit.reminderEnabled ||
        habit.isArchived ||
        habit.reminderHour == null ||
        habit.reminderMinute == null) {
      return;
    }

    switch (habit.frequency) {
      case Frequency.daily:
        await _scheduleDaily(habit);
        return;
      case Frequency.weekly:
        await _scheduleWeekly(habit);
        return;
      case Frequency.oddDays:
      case Frequency.evenDays:
        await _scheduleOddEven(habit);
        return;
    }
  }

  Future<void> cancelHabitReminders(String habitId) async {
    if (_isTestEnvironment) {
      return;
    }
    final baseId = _baseNotificationId(habitId);
    for (int i = 0; i < _notificationsPerHabit; i++) {
      await _notifications.cancel(baseId + i);
    }
  }

  Future<void> _scheduleDaily(Habit habit) async {
    final now = tz.TZDateTime.now(tz.local);
    final start = _startDateTimeAtReminder(habit);
    final earliestCandidate = start.isAfter(now) ? start : now;
    final earliest = _firstAllowedDateTimeOnOrAfter(earliestCandidate, habit);
    final when = _nextTimeAtOrAfter(
      habit.reminderHour!,
      habit.reminderMinute!,
      earliest: earliest,
      habit: habit,
    );
    await _notifications.zonedSchedule(
      _baseNotificationId(habit.id),
      habit.name,
      'Time for your habit: ${habit.name}',
      when,
      _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> _scheduleWeekly(Habit habit) async {
    final days =
        (habit.daysOfWeek ?? <int>[])
            .where((day) => day >= 1 && day <= 7)
            .toSet()
            .toList()
          ..sort();
    if (days.isEmpty) {
      return;
    }

    final baseId = _baseNotificationId(habit.id);
    final now = tz.TZDateTime.now(tz.local);
    final start = _startDateTimeAtReminder(habit);
    final earliestCandidate = start.isAfter(now) ? start : now;
    final earliest = _firstAllowedDateTimeOnOrAfter(earliestCandidate, habit);
    for (final day in days) {
      final when = _nextWeekdayTime(
        day,
        habit.reminderHour!,
        habit.reminderMinute!,
        earliest: earliest,
        habit: habit,
      );
      await _notifications.zonedSchedule(
        baseId + day,
        habit.name,
        'Time for your habit: ${habit.name}',
        when,
        _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  Future<void> _scheduleOddEven(Habit habit) async {
    final now = DateTime.now();
    final baseId = _baseNotificationId(habit.id);
    int slot = 0;
    DateTime day = DateTime(now.year, now.month, now.day);
    final startDate = DateTime(
      habit.startDate.year,
      habit.startDate.month,
      habit.startDate.day,
    );
    if (startDate.isAfter(day)) {
      day = startDate;
    }

    while (slot < _oddEvenSchedules) {
      final isMatchingDay = habit.frequency == Frequency.oddDays
          ? day.day.isOdd
          : day.day.isEven;
      if (isMatchingDay) {
        final localDateTime = DateTime(
          day.year,
          day.month,
          day.day,
          habit.reminderHour!,
          habit.reminderMinute!,
        );
        if (localDateTime.isAfter(now) &&
            !_isPausedOnDate(habit, DateTime(day.year, day.month, day.day))) {
          final when = tz.TZDateTime.from(localDateTime, tz.local);
          await _notifications.zonedSchedule(
            baseId + slot,
            habit.name,
            'Time for your habit: ${habit.name}',
            when,
            _details(),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          slot++;
        }
      }
      day = day.add(const Duration(days: 1));
    }
  }

  tz.TZDateTime _startDateTimeAtReminder(Habit habit) {
    return tz.TZDateTime(
      tz.local,
      habit.startDate.year,
      habit.startDate.month,
      habit.startDate.day,
      habit.reminderHour!,
      habit.reminderMinute!,
    );
  }

  tz.TZDateTime _nextTimeAtOrAfter(
    int hour,
    int minute, {
    required tz.TZDateTime earliest,
    required Habit habit,
  }) {
    var scheduled = tz.TZDateTime(
      tz.local,
      earliest.year,
      earliest.month,
      earliest.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(earliest)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    while (_isPausedOnDate(habit, scheduled)) {
      scheduled = scheduled.add(const Duration(days: 1));
      scheduled = tz.TZDateTime(
        tz.local,
        scheduled.year,
        scheduled.month,
        scheduled.day,
        hour,
        minute,
      );
    }
    return scheduled;
  }

  tz.TZDateTime _nextWeekdayTime(
    int weekday,
    int hour,
    int minute, {
    required tz.TZDateTime earliest,
    required Habit habit,
  }) {
    var scheduled = tz.TZDateTime(
      tz.local,
      earliest.year,
      earliest.month,
      earliest.day,
      hour,
      minute,
    );
    while (scheduled.weekday != weekday || !scheduled.isAfter(earliest)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    while (_isPausedOnDate(habit, scheduled)) {
      scheduled = scheduled.add(const Duration(days: 1));
      while (scheduled.weekday != weekday) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      scheduled = tz.TZDateTime(
        tz.local,
        scheduled.year,
        scheduled.month,
        scheduled.day,
        hour,
        minute,
      );
    }
    return scheduled;
  }

  bool _isPausedOnDate(Habit habit, DateTime date) {
    final settingsBox = Hive.box<dynamic>(HiveBoxNames.appSettings);
    final pausePeriods = loadPausePeriods(settingsBox);
    return isPausedOnDate(pausePeriods, date) ||
        isPausedOnDate(habit.pausePeriods, date);
  }

  tz.TZDateTime _firstAllowedDateTimeOnOrAfter(tz.TZDateTime dateTime, Habit habit) {
    var candidate = tz.TZDateTime(
      tz.local,
      dateTime.year,
      dateTime.month,
      dateTime.day,
      dateTime.hour,
      dateTime.minute,
    );
    while (_isPausedOnDate(habit, schedule_utils.normalizeDate(candidate))) {
      final nextDay = candidate.add(const Duration(days: 1));
      candidate = tz.TZDateTime(
        tz.local,
        nextDay.year,
        nextDay.month,
        nextDay.day,
        dateTime.hour,
        dateTime.minute,
      );
    }
    return candidate;
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Habit Reminders',
        channelDescription: 'Reminders for your habits',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  int _baseNotificationId(String habitId) {
    final hash = _stableHash(habitId) % 20000000;
    return hash * _notificationsPerHabit;
  }

  int _stableHash(String value) {
    int hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
