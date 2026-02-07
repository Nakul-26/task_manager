import 'package:flutter/material.dart';

enum HabitType {
  binary,
  counted,
}

enum Frequency {
  daily,
  weekly,
}

class Habit {
  late String id;
  late String name;
  late bool isImportant;
  late String description;
  late HabitType type;
  late Frequency frequency;
  late List<int>? daysOfWeek; // 1 for Monday, 7 for Sunday
  late int? timesPerDay;
  late Color color;
  late DateTime createdAt;
  late int sortOrder;

  Habit({
    required this.id,
    required this.name,
    this.isImportant = false,
    required this.description,
    this.type = HabitType.binary,
    this.frequency = Frequency.daily,
    this.daysOfWeek,
    this.timesPerDay,
    this.color = Colors.blue,
    required this.createdAt,
    this.sortOrder = -1,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'isImportant': isImportant,
      'description': description,
      'type': type.index,
      'frequency': frequency.index,
      'daysOfWeek': daysOfWeek,
      'timesPerDay': timesPerDay,
      'color': color.toARGB32(),
      'createdAt': createdAt.toIso8601String(),
      'sortOrder': sortOrder,
    };
  }

  factory Habit.fromMap(Map<String, dynamic> map) {
    return Habit(
      id: map['id'],
      name: map['name'],
      isImportant: map['isImportant'] ?? false,
      description: map['description'] ?? '',
      type: HabitType.values[map['type'] ?? 0],
      frequency: Frequency.values[map['frequency'] ?? 0],
      daysOfWeek: map['daysOfWeek'] != null ? List<int>.from(map['daysOfWeek']) : null,
      timesPerDay: map['timesPerDay'],
      color: Color(map['color'] ?? Colors.blue.toARGB32()),
      createdAt: DateTime.parse(map['createdAt']),
      sortOrder: map['sortOrder'] ?? -1,
    );
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
