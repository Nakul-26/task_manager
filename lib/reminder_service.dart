import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive/hive.dart';
import 'package:habit_tracker/models.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();

  static const int _notificationsPerHabit = 100;
  static const int _oddEvenSchedules = 60;
  static const String _channelId = 'habit_reminders';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    tz.initializeTimeZones();
    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      // Fallback to default timezone location if device timezone lookup fails.
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
    await initialize();
    final habits = habitBox.values
        .map((value) => Habit.fromMap(Map<String, dynamic>.from(value)))
        .toList();

    for (final habit in habits) {
      await syncHabitReminder(habit);
    }
  }

  Future<void> syncHabitReminder(Habit habit) async {
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
    final baseId = _baseNotificationId(habitId);
    for (int i = 0; i < _notificationsPerHabit; i++) {
      await _notifications.cancel(baseId + i);
    }
  }

  Future<void> _scheduleDaily(Habit habit) async {
    final when = _nextTimeTodayOrTomorrow(
      habit.reminderHour!,
      habit.reminderMinute!,
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
    for (final day in days) {
      final when = _nextWeekdayTime(
        day,
        habit.reminderHour!,
        habit.reminderMinute!,
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
        if (localDateTime.isAfter(now)) {
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

  tz.TZDateTime _nextTimeTodayOrTomorrow(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextWeekdayTime(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
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
