import 'package:flutter/material.dart';

enum HabitType { binary, counted }

enum Frequency { daily, weekly, oddDays, evenDays }

enum PriorityLevel { core, secondary, optional }

extension PriorityLevelInfo on PriorityLevel {
  String get displayName {
    switch (this) {
      case PriorityLevel.core:
        return 'Core';
      case PriorityLevel.secondary:
        return 'Secondary';
      case PriorityLevel.optional:
        return 'Optional';
    }
  }

  int get levelNumber => index + 1;

  int get xpReward {
    switch (this) {
      case PriorityLevel.core:
        return 10;
      case PriorityLevel.secondary:
        return 5;
      case PriorityLevel.optional:
        return 2;
    }
  }

  Color get accentColor {
    switch (this) {
      case PriorityLevel.core:
        return Colors.red;
      case PriorityLevel.secondary:
        return Colors.orange;
      case PriorityLevel.optional:
        return Colors.green;
    }
  }
}

class PausePeriod {
  late DateTime startDate;
  late DateTime endDate;
  late String description;

  PausePeriod({
    required DateTime startDate,
    required DateTime endDate,
    this.description = '',
  }) : startDate = DateTime(startDate.year, startDate.month, startDate.day),
       endDate = DateTime(endDate.year, endDate.month, endDate.day);

  Map<String, dynamic> toMap() {
    return {
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'description': description,
    };
  }

  factory PausePeriod.fromMap(Map<String, dynamic> map) {
    return PausePeriod(
      startDate: DateTime.parse(map['startDate']),
      endDate: DateTime.parse(map['endDate']),
      description: map['description'] ?? '',
    );
  }
}

class Habit {
  late String id;
  late String name;
  late bool isImportant;
  late int importanceScore;
  late bool isArchived;
  late String description;
  late HabitType type;
  late Frequency frequency;
  late List<int>? daysOfWeek; // 1 for Monday, 7 for Sunday
  late int? timesPerDay;
  late bool reminderEnabled;
  late int? reminderHour;
  late int? reminderMinute;
  late bool useTimeVisibility;
  late int? visibleAfterHour;
  late int? visibleAfterMinute;
  late int? timerMinutes;
  late Color color;
  late PriorityLevel priorityLevel;
  late DateTime startDate;
  late DateTime? endDate;
  late DateTime createdAt;
  late DateTime? archivedAt;
  late int sortOrder;

  Habit({
    required this.id,
    required this.name,
    this.isImportant = false,
    this.importanceScore = 0,
    this.isArchived = false,
    required this.description,
    this.type = HabitType.binary,
    this.frequency = Frequency.daily,
    this.daysOfWeek,
    this.timesPerDay,
    this.reminderEnabled = false,
    this.reminderHour,
    this.reminderMinute,
    this.useTimeVisibility = false,
    this.visibleAfterHour,
    this.visibleAfterMinute,
    this.timerMinutes,
    this.color = Colors.blue,
    this.priorityLevel = PriorityLevel.core,
    DateTime? startDate,
    this.endDate,
    required this.createdAt,
    this.archivedAt,
    this.sortOrder = -1,
  }) : startDate = startDate ?? createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'isImportant': isImportant,
      'importanceScore': importanceScore,
      'isArchived': isArchived,
      'description': description,
      'type': type.index,
      'frequency': frequency.index,
      'daysOfWeek': daysOfWeek,
      'timesPerDay': timesPerDay,
      'reminderEnabled': reminderEnabled,
      'reminderHour': reminderHour,
      'reminderMinute': reminderMinute,
      'useTimeVisibility': useTimeVisibility,
      'visibleAfterHour': visibleAfterHour,
      'visibleAfterMinute': visibleAfterMinute,
      'timerMinutes': timerMinutes,
      'color': color.toARGB32(),
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'priorityLevel': priorityLevel.index,
      'createdAt': createdAt.toIso8601String(),
      'archivedAt': archivedAt?.toIso8601String(),
      'sortOrder': sortOrder,
    };
  }

  factory Habit.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.parse(map['createdAt']);
    final parsedImportanceScore = _parseImportanceScore(map['importanceScore']);
    final importanceScore =
        parsedImportanceScore ?? ((map['isImportant'] ?? false) ? 1 : 0);
    return Habit(
      id: map['id'],
      name: map['name'],
      isImportant: importanceScore > 0,
      importanceScore: importanceScore,
      isArchived: map['isArchived'] ?? false,
      description: map['description'] ?? '',
      type: HabitType.values[map['type'] ?? 0],
      frequency: Frequency.values[map['frequency'] ?? 0],
      daysOfWeek: map['daysOfWeek'] != null
          ? List<int>.from(map['daysOfWeek'])
          : null,
      timesPerDay: map['timesPerDay'],
      reminderEnabled: map['reminderEnabled'] ?? false,
      reminderHour: map['reminderHour'],
      reminderMinute: map['reminderMinute'],
      useTimeVisibility: map['useTimeVisibility'] ?? false,
      visibleAfterHour: map['visibleAfterHour'],
      visibleAfterMinute: map['visibleAfterMinute'],
      timerMinutes: map['timerMinutes'],
      color: Color(map['color'] ?? Colors.blue.toARGB32()),
      priorityLevel: _parsePriorityLevel(map['priorityLevel']),
      startDate: map['startDate'] != null
          ? DateTime.parse(map['startDate'])
          : createdAt,
      endDate: map['endDate'] != null ? DateTime.parse(map['endDate']) : null,
      createdAt: createdAt,
      archivedAt: map['archivedAt'] != null
          ? DateTime.parse(map['archivedAt'])
          : null,
      sortOrder: map['sortOrder'] ?? -1,
    );
  }

  static int? _parseImportanceScore(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static PriorityLevel _parsePriorityLevel(dynamic value) {
    if (value is int && value >= 0 && value < PriorityLevel.values.length) {
      return PriorityLevel.values[value];
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null &&
          parsed >= 0 &&
          parsed < PriorityLevel.values.length) {
        return PriorityLevel.values[parsed];
      }
    }
    return PriorityLevel.core;
  }
}

class DailyLog {
  late String date; // YYYY-MM-DD
  late String habitId;
  late bool completed;
  late int? count; // for counted habits

  DailyLog({
    required this.date,
    required this.habitId,
    this.completed = false,
    this.count,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'habitId': habitId,
      'completed': completed,
      'count': count,
    };
  }

  factory DailyLog.fromMap(Map<String, dynamic> map) {
    return DailyLog(
      date: map['date'],
      habitId: map['habitId'],
      completed: map['completed'] ?? false,
      count: map['count'],
    );
  }
}
