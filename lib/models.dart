import 'package:flutter/material.dart';

enum HabitType { binary, counted }

enum Frequency { daily, weekly, oddDays, evenDays }

enum ExecutionContext { deepWork, college, quickTask }

enum PriorityLevel { core, secondary, optional }

const Map<String, IconData> executionEnvironmentIcons = {
  'psychology': Icons.psychology,
  'school': Icons.school,
  'flash_on': Icons.flash_on,
  'home': Icons.home,
  'work': Icons.work,
  'book': Icons.book,
  'timer': Icons.timer,
  'task_alt': Icons.task_alt,
  'self_improvement': Icons.self_improvement,
  'laptop': Icons.laptop,
  'coffee': Icons.coffee,
  'directions_run': Icons.directions_run,
};

final Map<int, String> _executionEnvironmentIconKeysByCodePoint = {
  Icons.psychology.codePoint: 'psychology',
  Icons.school.codePoint: 'school',
  Icons.flash_on.codePoint: 'flash_on',
  Icons.home.codePoint: 'home',
  Icons.work.codePoint: 'work',
  Icons.book.codePoint: 'book',
  Icons.timer.codePoint: 'timer',
  Icons.task_alt.codePoint: 'task_alt',
  Icons.self_improvement.codePoint: 'self_improvement',
  Icons.laptop.codePoint: 'laptop',
  Icons.coffee.codePoint: 'coffee',
  Icons.directions_run.codePoint: 'directions_run',
};

IconData executionEnvironmentIconForKey(String key) {
  return executionEnvironmentIcons[key] ?? Icons.circle;
}

String executionEnvironmentIconKeyFor(IconData icon) {
  return _executionEnvironmentIconKeysByCodePoint[icon.codePoint] ??
      'psychology';
}

bool _sameIntList(List<int>? a, List<int>? b) {
  if (a == null || b == null) {
    return a == b;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

extension PriorityLevelInfo on PriorityLevel {
  String get displayName {
    switch (this) {
      case PriorityLevel.core:
        return 'Core';
      case PriorityLevel.secondary:
        return 'Important';
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

extension ExecutionContextInfo on ExecutionContext {
  String get displayName {
    switch (this) {
      case ExecutionContext.deepWork:
        return 'Deep Work';
      case ExecutionContext.college:
        return 'College';
      case ExecutionContext.quickTask:
        return 'Quick Task';
    }
  }

  String get explanation {
    switch (this) {
      case ExecutionContext.deepWork:
        return 'Requires uninterrupted focus.';
      case ExecutionContext.college:
        return 'Works in classroom or campus gaps.';
      case ExecutionContext.quickTask:
        return 'Fits short, low-friction moments.';
    }
  }
}

class ExecutionEnvironment {
  final String id;
  final String name;
  final String description;
  final Color color;
  final String iconKey;
  final bool isBuiltIn;
  final int sortOrder;

  const ExecutionEnvironment({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.iconKey,
    this.isBuiltIn = false,
    this.sortOrder = -1,
  });

  IconData get icon => executionEnvironmentIconForKey(iconKey);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color.toARGB32(),
      'iconKey': iconKey,
      'iconCodePoint': icon.codePoint,
      'iconFontFamily': icon.fontFamily,
      'iconFontPackage': icon.fontPackage,
      'isBuiltIn': isBuiltIn,
      'sortOrder': sortOrder,
    };
  }

  factory ExecutionEnvironment.fromMap(Map<String, dynamic> map) {
    final iconKey = _parseExecutionEnvironmentIconKey(map);
    return ExecutionEnvironment(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      color: Color(map['color'] ?? Colors.blue.toARGB32()),
      iconKey: iconKey,
      isBuiltIn: map['isBuiltIn'] ?? false,
      sortOrder: map['sortOrder'] ?? -1,
    );
  }
}

String _parseExecutionEnvironmentIconKey(Map<String, dynamic> map) {
  final rawKey = map['iconKey'];
  if (rawKey is String && rawKey.isNotEmpty) {
    return rawKey;
  }

  final rawCodePoint = map['iconCodePoint'];
  if (rawCodePoint is int) {
    return _executionEnvironmentIconKeysByCodePoint[rawCodePoint] ??
        'psychology';
  }

  if (rawCodePoint is num) {
    return _executionEnvironmentIconKeysByCodePoint[rawCodePoint.toInt()] ??
        'psychology';
  }

  return 'psychology';
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
  late ExecutionContext executionContext;
  late String environmentId;
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
  late List<PausePeriod> pausePeriods;
  late List<HabitRuleSnapshot> ruleHistory;

  Habit({
    required this.id,
    required this.name,
    this.isImportant = false,
    this.importanceScore = 0,
    this.isArchived = false,
    required this.description,
    this.type = HabitType.binary,
    this.frequency = Frequency.daily,
    this.executionContext = ExecutionContext.quickTask,
    String? environmentId,
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
    List<PausePeriod>? pausePeriods,
    List<HabitRuleSnapshot>? ruleHistory,
  }) : environmentId = environmentId ?? _defaultEnvironmentIdFor(executionContext),
       startDate = startDate ?? createdAt {
    this.pausePeriods = pausePeriods ?? [];
    this.ruleHistory =
        (ruleHistory == null || ruleHistory.isEmpty)
            ? [
                HabitRuleSnapshot.fromHabit(
                  this,
                  effectiveFrom: this.startDate,
                ),
              ]
            : List<HabitRuleSnapshot>.from(ruleHistory)
            ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
  }

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
      'executionContext': executionContext.index,
      'environmentId': environmentId,
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
      'pausePeriods': pausePeriods.map((period) => period.toMap()).toList(),
      'ruleHistory': ruleHistory.map((rule) => rule.toMap()).toList(),
    };
  }

  Map<String, dynamic> toExportMap() {
    final map = <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'ruleHistory': ruleHistory.map((rule) => rule.toExportMap()).toList(),
    };

    if (isImportant || importanceScore > 0) {
      map['importanceScore'] = importanceScore;
    }
    if (isArchived) {
      map['isArchived'] = true;
    }
    if (type != HabitType.binary) {
      map['type'] = type.index;
    }
    if (frequency != Frequency.daily) {
      map['frequency'] = frequency.index;
    }
    if (executionContext != ExecutionContext.quickTask) {
      map['executionContext'] = executionContext.index;
    }
    if (environmentId != _defaultEnvironmentIdFor(executionContext)) {
      map['environmentId'] = environmentId;
    }
    if (daysOfWeek != null && daysOfWeek!.isNotEmpty) {
      map['daysOfWeek'] = List<int>.from(daysOfWeek!);
    }
    if (timesPerDay != null) {
      map['timesPerDay'] = timesPerDay;
    }
    if (reminderEnabled) {
      map['reminderEnabled'] = true;
    }
    if (reminderHour != null) {
      map['reminderHour'] = reminderHour;
    }
    if (reminderMinute != null) {
      map['reminderMinute'] = reminderMinute;
    }
    if (useTimeVisibility) {
      map['useTimeVisibility'] = true;
    }
    if (visibleAfterHour != null) {
      map['visibleAfterHour'] = visibleAfterHour;
    }
    if (visibleAfterMinute != null) {
      map['visibleAfterMinute'] = visibleAfterMinute;
    }
    if (timerMinutes != null) {
      map['timerMinutes'] = timerMinutes;
    }
    if (color.toARGB32() != Colors.blue.toARGB32()) {
      map['color'] = color.toARGB32();
    }
    if (priorityLevel != PriorityLevel.core) {
      map['priorityLevel'] = priorityLevel.index;
    }
    if (startDate != createdAt) {
      map['startDate'] = startDate.toIso8601String();
    }
    if (endDate != null) {
      map['endDate'] = endDate!.toIso8601String();
    }
    if (archivedAt != null) {
      map['archivedAt'] = archivedAt!.toIso8601String();
    }
    if (sortOrder >= 0) {
      map['sortOrder'] = sortOrder;
    }
    if (pausePeriods.isNotEmpty) {
      map['pausePeriods'] = pausePeriods.map((period) => period.toMap()).toList();
    }

    return map;
  }

  factory Habit.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.parse(map['createdAt']);
    final parsedImportanceScore = _parseImportanceScore(map['importanceScore']);
    final importanceScore =
        parsedImportanceScore ?? ((map['isImportant'] ?? false) ? 1 : 0);
    final parsedRuleHistory = map['ruleHistory'];
    final ruleHistory = parsedRuleHistory is List
        ? parsedRuleHistory
            .map((entry) => HabitRuleSnapshot.fromMap(Map<String, dynamic>.from(entry as Map)))
            .toList()
        : <HabitRuleSnapshot>[];
    final parsedPausePeriods = map['pausePeriods'];
    final pausePeriods = parsedPausePeriods is List
        ? parsedPausePeriods
            .map((entry) => PausePeriod.fromMap(Map<String, dynamic>.from(entry as Map)))
            .toList()
        : <PausePeriod>[];
    return Habit(
      id: map['id'],
      name: map['name'],
      isImportant: importanceScore > 0,
      importanceScore: importanceScore,
      isArchived: map['isArchived'] ?? false,
      description: map['description'] ?? '',
      type: HabitType.values[map['type'] ?? 0],
      frequency: Frequency.values[map['frequency'] ?? 0],
      executionContext: _parseExecutionContext(map['executionContext']),
      environmentId: _parseEnvironmentId(map),
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
      pausePeriods: pausePeriods,
      ruleHistory: ruleHistory.isEmpty
          ? [
              HabitRuleSnapshot(
                effectiveFrom: map['startDate'] != null
                    ? DateTime.parse(map['startDate'])
                    : createdAt,
                type: HabitType.values[map['type'] ?? 0],
                frequency: Frequency.values[map['frequency'] ?? 0],
                daysOfWeek: map['daysOfWeek'] != null
                    ? List<int>.from(map['daysOfWeek'])
                    : null,
                timesPerDay: map['timesPerDay'],
              ),
            ]
          : ruleHistory,
    );
  }

  bool matchesContext(ExecutionContext? context) {
    if (context == null) {
      return true;
    }
    return executionContext == context;
  }

  bool get isStrategicAnchor {
    return priorityLevel == PriorityLevel.core || importanceScore >= 4;
  }

  String get strategicLabel {
    if (importanceScore >= 4) {
      return 'Strategic anchor';
    }
    switch (priorityLevel) {
      case PriorityLevel.core:
        return 'Strategic anchor';
      case PriorityLevel.secondary:
        return 'Support task';
      case PriorityLevel.optional:
        return 'Exploration task';
    }
  }

  String get contextLabel => executionContext.displayName;

  HabitRuleSnapshot get currentRule => ruleHistory.last;

  HabitRuleSnapshot ruleForDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    HabitRuleSnapshot selected = ruleHistory.first;
    for (final rule in ruleHistory) {
      if (!rule.effectiveFrom.isAfter(normalizedDate)) {
        selected = rule;
      } else {
        break;
      }
    }
    return selected;
  }

  bool hasSameRule({
    required HabitType type,
    required Frequency frequency,
    required List<int>? daysOfWeek,
    required int? timesPerDay,
  }) {
    final current = currentRule;
    return current.type == type &&
        current.frequency == frequency &&
        _sameIntList(current.daysOfWeek, daysOfWeek) &&
        current.timesPerDay == timesPerDay;
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

  static ExecutionContext _parseExecutionContext(dynamic value) {
    if (value is int &&
        value >= 0 &&
        value < ExecutionContext.values.length) {
      return ExecutionContext.values[value];
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null &&
          parsed >= 0 &&
          parsed < ExecutionContext.values.length) {
        return ExecutionContext.values[parsed];
      }
      for (final context in ExecutionContext.values) {
        if (context.name.toLowerCase() == value.toLowerCase()) {
          return context;
        }
      }
    }
    return ExecutionContext.quickTask;
  }

  static String _parseEnvironmentId(Map<String, dynamic> map) {
    final environmentId = map['environmentId'];
    if (environmentId is String && environmentId.trim().isNotEmpty) {
      return environmentId;
    }
    return _defaultEnvironmentIdFor(
      _parseExecutionContext(map['executionContext']),
    );
  }

  static String _defaultEnvironmentIdFor(ExecutionContext context) {
    switch (context) {
      case ExecutionContext.deepWork:
        return 'deepWork';
      case ExecutionContext.college:
        return 'college';
      case ExecutionContext.quickTask:
        return 'quickTask';
    }
  }
}

class HabitRuleSnapshot {
  late DateTime effectiveFrom;
  late HabitType type;
  late Frequency frequency;
  late List<int>? daysOfWeek;
  late int? timesPerDay;

  HabitRuleSnapshot({
    required DateTime effectiveFrom,
    required this.type,
    required this.frequency,
    this.daysOfWeek,
    this.timesPerDay,
  }) : effectiveFrom = DateTime(
         effectiveFrom.year,
         effectiveFrom.month,
         effectiveFrom.day,
       );

  factory HabitRuleSnapshot.fromHabit(
    Habit habit, {
    DateTime? effectiveFrom,
  }) {
    return HabitRuleSnapshot(
      effectiveFrom: effectiveFrom ?? habit.startDate,
      type: habit.type,
      frequency: habit.frequency,
      daysOfWeek: habit.daysOfWeek == null
          ? null
          : List<int>.from(habit.daysOfWeek!),
      timesPerDay: habit.timesPerDay,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'effectiveFrom': effectiveFrom.toIso8601String(),
      'type': type.index,
      'frequency': frequency.index,
      'daysOfWeek': daysOfWeek,
      'timesPerDay': timesPerDay,
    };
  }

  Map<String, dynamic> toExportMap() {
    final map = <String, dynamic>{
      'effectiveFrom': effectiveFrom.toIso8601String(),
    };

    if (type != HabitType.binary) {
      map['type'] = type.index;
    }
    if (frequency != Frequency.daily) {
      map['frequency'] = frequency.index;
    }
    if (daysOfWeek != null && daysOfWeek!.isNotEmpty) {
      map['daysOfWeek'] = List<int>.from(daysOfWeek!);
    }
    if (timesPerDay != null) {
      map['timesPerDay'] = timesPerDay;
    }

    return map;
  }

  factory HabitRuleSnapshot.fromMap(Map<String, dynamic> map) {
    return HabitRuleSnapshot(
      effectiveFrom: map['effectiveFrom'] != null
          ? DateTime.parse(map['effectiveFrom'])
          : DateTime.now(),
      type: HabitType.values[map['type'] ?? 0],
      frequency: Frequency.values[map['frequency'] ?? 0],
      daysOfWeek: map['daysOfWeek'] != null
          ? List<int>.from(map['daysOfWeek'])
          : null,
      timesPerDay: map['timesPerDay'],
    );
  }
}

class DailyLog {
  late String date; // YYYY-MM-DD
  late String habitId;
  late bool completed;
  late int? count; // for counted habits
  late int? quality; // 1 to 4
  late HabitType? type;
  late Frequency? frequency;
  late List<int>? daysOfWeek;
  late int? timesPerDay;

  DailyLog({
    required this.date,
    required this.habitId,
    this.completed = false,
    this.count,
    this.quality,
    this.type,
    this.frequency,
    this.daysOfWeek,
    this.timesPerDay,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'habitId': habitId,
      'completed': completed,
      'count': count,
      'quality': quality,
      'type': type?.index,
      'frequency': frequency?.index,
      'daysOfWeek': daysOfWeek,
      'timesPerDay': timesPerDay,
    };
  }

  factory DailyLog.fromMap(Map<String, dynamic> map) {
    return DailyLog(
      date: map['date'],
      habitId: map['habitId'],
      completed: map['completed'] ?? false,
      count: map['count'],
      quality: map['quality'],
      type: map['type'] != null ? HabitType.values[map['type']] : null,
      frequency:
          map['frequency'] != null ? Frequency.values[map['frequency']] : null,
      daysOfWeek: map['daysOfWeek'] != null
          ? List<int>.from(map['daysOfWeek'])
          : null,
      timesPerDay: map['timesPerDay'],
    );
  }
}
