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
  late int? timesPerWeek;
  late int? timesPerDay;
  late Color color;
  late DateTime createdAt;

  Habit({
    required this.id,
    required this.name,
    this.isImportant = false,
    required this.description,
    this.type = HabitType.binary,
    this.frequency = Frequency.daily,
    this.daysOfWeek,
    this.timesPerWeek,
    this.timesPerDay,
    this.color = Colors.blue,
    required this.createdAt,
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
      'timesPerWeek': timesPerWeek,
      'timesPerDay': timesPerDay,
      'color': color.value,
      'createdAt': createdAt.toIso8601String(),
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
      timesPerWeek: map['timesPerWeek'],
      timesPerDay: map['timesPerDay'],
      color: Color(map['color'] ?? Colors.blue.value),
      createdAt: DateTime.parse(map['createdAt']),
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