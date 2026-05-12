import 'package:flutter/material.dart';
import 'package:habit_tracker/models.dart';
import 'package:hive/hive.dart';

const String executionEnvironmentsKey = 'executionEnvironments';

List<ExecutionEnvironment> defaultExecutionEnvironments() {
  return const [
    ExecutionEnvironment(
      id: 'deepWork',
      name: 'Deep Work',
      description: 'Requires uninterrupted focus.',
      color: Colors.red,
      iconKey: 'psychology',
      isBuiltIn: true,
      sortOrder: 0,
    ),
    ExecutionEnvironment(
      id: 'college',
      name: 'College',
      description: 'Works in classroom or campus gaps.',
      color: Colors.orange,
      iconKey: 'school',
      isBuiltIn: true,
      sortOrder: 1,
    ),
    ExecutionEnvironment(
      id: 'quickTask',
      name: 'Quick Task',
      description: 'Fits short, low-friction moments.',
      color: Colors.blue,
      iconKey: 'flash_on',
      isBuiltIn: true,
      sortOrder: 2,
    ),
  ];
}

List<ExecutionEnvironment> loadExecutionEnvironments(Box<dynamic> settingsBox) {
  final stored = settingsBox.get(executionEnvironmentsKey);
  if (stored is List && stored.isNotEmpty) {
    final environments = stored
        .whereType<Map>()
        .map((entry) => ExecutionEnvironment.fromMap(Map<String, dynamic>.from(entry)))
        .toList();
    if (environments.isNotEmpty) {
      environments.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return environments;
    }
  }
  return defaultExecutionEnvironments();
}

Future<void> saveExecutionEnvironments(
  Box<dynamic> settingsBox,
  List<ExecutionEnvironment> environments,
) async {
  final normalized = List<ExecutionEnvironment>.from(environments)
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final payload = normalized.asMap().entries.map((entry) {
    final env = entry.value;
    return ExecutionEnvironment(
      id: env.id,
      name: env.name,
      description: env.description,
      color: env.color,
      iconKey: env.iconKey,
      isBuiltIn: env.isBuiltIn,
      sortOrder: entry.key,
    ).toMap();
  }).toList();
  await settingsBox.put(executionEnvironmentsKey, payload);
}

ExecutionEnvironment? findExecutionEnvironment(
  List<ExecutionEnvironment> environments,
  String id,
) {
  for (final environment in environments) {
    if (environment.id == id) {
      return environment;
    }
  }
  return null;
}

String environmentDisplayName(
  List<ExecutionEnvironment> environments,
  String id, {
  String fallback = 'Unknown environment',
}) {
  return findExecutionEnvironment(environments, id)?.name ?? fallback;
}
