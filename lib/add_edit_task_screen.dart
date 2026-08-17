import 'package:flutter/material.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:habit_tracker/utils/execution_environment_utils.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

class AddEditTaskScreen extends StatefulWidget {
  final OneTimeTask? task;

  const AddEditTaskScreen({super.key, this.task});

  @override
  State<AddEditTaskScreen> createState() => _AddEditTaskScreenState();
}

class _AddEditTaskScreenState extends State<AddEditTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late Box<dynamic> _settingsBox;
  List<ExecutionEnvironment> _environments = const [];
  Set<String> _selectedEnvironmentIds = {};
  PriorityLevel _priorityLevel = PriorityLevel.core;
  DateTime? _dueDate;
  bool _reminderEnabled = false;
  TimeOfDay? _reminderTime;

  @override
  void initState() {
    super.initState();
    _settingsBox = Hive.box(HiveBoxNames.appSettings);
    _environments = loadExecutionEnvironments(_settingsBox);
    final task = widget.task;
    _nameController = TextEditingController(text: task?.name ?? '');
    _descriptionController = TextEditingController(
      text: task?.description ?? '',
    );
    if (task != null) {
      _selectedEnvironmentIds = task.environmentIds.toSet();
      _selectedEnvironmentIds.removeWhere(
        (id) => findExecutionEnvironment(_environments, id) == null,
      );
      _priorityLevel = task.priorityLevel;
      _dueDate = task.dueDate;
      _reminderEnabled = task.reminderEnabled;
      if (task.reminderHour != null && task.reminderMinute != null) {
        _reminderTime = TimeOfDay(
          hour: task.reminderHour!,
          minute: task.reminderMinute!,
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        _dueDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  void _clearDueDate() {
    setState(() {
      _dueDate = null;
    });
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _reminderTime = picked;
      });
    }
  }

  Future<void> _saveTask() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_reminderEnabled && _reminderTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a reminder time.')),
      );
      return;
    }
    if (_reminderEnabled && _dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set a due date to attach a reminder.'),
        ),
      );
      return;
    }

    final taskBox = Hive.box(HiveBoxNames.oneTimeTasks);
    final task = widget.task;
    int sortOrder = task?.sortOrder ?? -1;
    if (task == null) {
      final existingTasks = taskBox.values
          .map((e) => OneTimeTask.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      sortOrder = existingTasks.isEmpty
          ? 0
          : existingTasks
                    .map((t) => t.sortOrder)
                    .reduce((a, b) => a > b ? a : b) +
                1;
    }

    final newTask = OneTimeTask(
      id: task?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      dueDate: _dueDate,
      priorityLevel: _priorityLevel,
      environmentIds: _selectedEnvironmentIds.toList(),
      isDone: task?.isDone ?? false,
      completedAt: task?.completedAt,
      reminderEnabled: _reminderEnabled,
      reminderHour: _reminderEnabled ? _reminderTime?.hour : null,
      reminderMinute: _reminderEnabled ? _reminderTime?.minute : null,
      createdAt: task?.createdAt ?? DateTime.now(),
      sortOrder: sortOrder,
    );

    await taskBox.put(newTask.id, newTask.toMap());
    await ReminderService.instance.syncTaskReminder(newTask);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _deleteTask() async {
    final taskBox = Hive.box(HiveBoxNames.oneTimeTasks);
    await taskBox.delete(widget.task!.id);
    await ReminderService.instance.cancelTaskReminder(widget.task!.id);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'Add Task' : 'Edit Task'),
        actions: [
          if (widget.task != null)
            IconButton(icon: const Icon(Icons.delete), onPressed: _deleteTask),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PriorityLevel>(
                  initialValue: _priorityLevel,
                  decoration: const InputDecoration(
                    labelText: 'Priority Level',
                    border: OutlineInputBorder(),
                  ),
                  items: PriorityLevel.values.map((level) {
                    return DropdownMenuItem(
                      value: level,
                      child: Text(
                        'Level ${level.levelNumber} · ${level.displayName}',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _priorityLevel = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (_environments.isNotEmpty)
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Environment (optional)',
                      border: OutlineInputBorder(),
                      helperText: 'Where this task is realistically doable.',
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _environments.map((environment) {
                        final isSelected = _selectedEnvironmentIds.contains(
                          environment.id,
                        );
                        return FilterChip(
                          avatar: Icon(
                            environment.icon,
                            size: 18,
                            color: isSelected ? null : environment.color,
                          ),
                          label: Text(environment.name),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedEnvironmentIds.add(environment.id);
                              } else {
                                _selectedEnvironmentIds.remove(environment.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due date'),
                  subtitle: Text(
                    _dueDate == null ? 'No due date' : _formatDate(_dueDate!),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_dueDate != null)
                        IconButton(
                          tooltip: 'Clear due date',
                          icon: const Icon(Icons.clear),
                          onPressed: _clearDueDate,
                        ),
                      const Icon(Icons.calendar_today),
                    ],
                  ),
                  onTap: _pickDueDate,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reminder'),
                  subtitle: Text(
                    _reminderEnabled
                        ? (_reminderTime == null
                              ? 'Select reminder time'
                              : 'At ${_reminderTime!.format(context)}')
                        : 'Off',
                  ),
                  value: _reminderEnabled,
                  onChanged: (value) {
                    setState(() {
                      _reminderEnabled = value;
                    });
                  },
                ),
                if (_reminderEnabled)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reminder time'),
                    subtitle: Text(
                      _reminderTime?.format(context) ?? 'Not set',
                    ),
                    trailing: const Icon(Icons.schedule),
                    onTap: _pickReminderTime,
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saveTask,
                  icon: const Icon(Icons.check),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
