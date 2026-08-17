import 'package:flutter/material.dart';
import 'package:habit_tracker/add_edit_task_screen.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late Box<dynamic> _taskBox;

  @override
  void initState() {
    super.initState();
    _taskBox = Hive.box(HiveBoxNames.oneTimeTasks);
  }

  List<OneTimeTask> _loadTasks() {
    return _taskBox.values
        .map((e) => OneTimeTask.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  int _compareTasks(OneTimeTask a, OneTimeTask b) {
    final priorityCompare = a.priorityLevel.index.compareTo(
      b.priorityLevel.index,
    );
    if (priorityCompare != 0) {
      return priorityCompare;
    }
    if (a.dueDate != null && b.dueDate != null) {
      return a.dueDate!.compareTo(b.dueDate!);
    }
    return a.sortOrder.compareTo(b.sortOrder);
  }

  Future<void> _toggleDone(OneTimeTask task) async {
    task.isDone = !task.isDone;
    task.completedAt = task.isDone ? DateTime.now() : null;
    await _taskBox.put(task.id, task.toMap());
    await ReminderService.instance.syncTaskReminder(task);
    setState(() {});
  }

  Future<void> _deleteTask(OneTimeTask task) async {
    await _taskBox.delete(task.id);
    await ReminderService.instance.cancelTaskReminder(task.id);
    setState(() {});
  }

  Future<void> _openTask([OneTimeTask? task]) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => AddEditTaskScreen(task: task)));
    if (mounted) {
      setState(() {});
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildTaskTile(OneTimeTask task) {
    return Dismissible(
      key: ValueKey(task.id),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteTask(task),
      child: ListTile(
        leading: Checkbox(
          value: task.isDone,
          onChanged: (_) => _toggleDone(task),
        ),
        title: Text(
          task.name,
          style: task.isDone
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: task.dueDate != null
            ? Text('Due ${_formatDate(task.dueDate!)}')
            : null,
        trailing: Icon(
          Icons.flag,
          size: 18,
          color: task.priorityLevel.accentColor,
        ),
        onTap: () => _openTask(task),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _taskBox.listenable(),
      builder: (context, Box<dynamic> box, _) {
        final tasks = _loadTasks();
        final today = DateTime.now();
        final normalizedToday = DateTime(today.year, today.month, today.day);

        final pending = tasks.where((t) => !t.isDone).toList();
        final done = tasks.where((t) => t.isDone).toList()
          ..sort(
            (a, b) => (b.completedAt ?? b.createdAt).compareTo(
              a.completedAt ?? a.createdAt,
            ),
          );

        final overdue =
            pending
                .where(
                  (t) => t.dueDate != null && t.dueDate!.isBefore(normalizedToday),
                )
                .toList()
              ..sort(_compareTasks);
        final dueToday =
            pending
                .where(
                  (t) =>
                      t.dueDate != null &&
                      t.dueDate!.isAtSameMomentAs(normalizedToday),
                )
                .toList()
              ..sort(_compareTasks);
        final upcoming =
            pending
                .where(
                  (t) => t.dueDate != null && t.dueDate!.isAfter(normalizedToday),
                )
                .toList()
              ..sort(_compareTasks);
        final noDate = pending.where((t) => t.dueDate == null).toList()
          ..sort(_compareTasks);

        final sections = <MapEntry<String, List<OneTimeTask>>>[
          MapEntry('Overdue', overdue),
          MapEntry('Due Today', dueToday),
          MapEntry('Upcoming', upcoming),
          MapEntry('No Date', noDate),
          MapEntry('Done', done),
        ].where((entry) => entry.value.isNotEmpty).toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Tasks')),
          body: sections.isEmpty
              ? const Center(child: Text('No tasks yet. Tap + to add one.'))
              : ListView(
                  children: [
                    for (final section in sections) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          '${section.key} (${section.value.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      for (final task in section.value) _buildTaskTile(task),
                    ],
                  ],
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openTask(),
            backgroundColor: Colors.green,
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}
