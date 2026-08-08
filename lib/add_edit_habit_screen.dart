import 'package:flutter/material.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/manage_environments_screen.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:habit_tracker/utils/execution_environment_utils.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';

class AddEditHabitScreen extends StatefulWidget {
  final Habit? habit;
  final Future<void> Function(Habit habit)? onHabitSaved;
  final Future<void> Function(String habitId)? onHabitDeleted;

  const AddEditHabitScreen({
    super.key,
    this.habit,
    this.onHabitSaved,
    this.onHabitDeleted,
  });

  @override
  State<AddEditHabitScreen> createState() => _AddEditHabitScreenState();
}

class _AddEditHabitScreenState extends State<AddEditHabitScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _name;
  late String _description;
  late Box<dynamic> _settingsBox;
  HabitType _type = HabitType.binary;
  Frequency _frequency = Frequency.daily;
  Set<String> _selectedEnvironmentIds = {'quickTask'};
  List<ExecutionEnvironment> _environments = const [];
  int? _timesPerDay;
  int? _timerMinutes;
  List<int> _daysOfWeek = [];
  Color _color = Colors.blue;
  PriorityLevel _priorityLevel = PriorityLevel.core;
  bool _isImportant = false;
  int _importanceScore = 0;
  bool _reminderEnabled = false;
  TimeOfDay? _reminderTime;
  bool _useTimeVisibility = false;
  TimeOfDay? _visibleAfterTime;
  late DateTime _startDate;
  DateTime? _endDate;

  String _frequencyLabel(Frequency frequency) {
    switch (frequency) {
      case Frequency.daily:
        return 'Daily';
      case Frequency.weekly:
        return 'Weekly';
      case Frequency.oddDays:
        return 'Odd days';
      case Frequency.evenDays:
        return 'Even days';
    }
  }

  @override
  void initState() {
    super.initState();
    _settingsBox = Hive.box(HiveBoxNames.appSettings);
    _environments = loadExecutionEnvironments(_settingsBox);
    if (widget.habit != null) {
      _name = widget.habit!.name;
      _description = widget.habit!.description;
      _type = widget.habit!.type;
      _frequency = widget.habit!.frequency;
      _selectedEnvironmentIds = widget.habit!.environmentIds.toSet();
      _selectedEnvironmentIds.removeWhere(
        (id) => findExecutionEnvironment(_environments, id) == null,
      );
      if (_selectedEnvironmentIds.isEmpty && _environments.isNotEmpty) {
        _selectedEnvironmentIds = {_environments.first.id};
      }
      _timesPerDay = widget.habit!.timesPerDay;
      _timerMinutes = widget.habit!.timerMinutes;
      _daysOfWeek = widget.habit!.daysOfWeek ?? [];
      _color = widget.habit!.color;
      _priorityLevel = widget.habit!.priorityLevel;
      _isImportant = widget.habit!.isImportant;
      _importanceScore = widget.habit!.importanceScore;
      _startDate = _normalizeDate(widget.habit!.startDate);
      _endDate = widget.habit!.endDate != null
          ? _normalizeDate(widget.habit!.endDate!)
          : null;
      _reminderEnabled = widget.habit!.reminderEnabled;
      if (widget.habit!.reminderHour != null &&
          widget.habit!.reminderMinute != null) {
        _reminderTime = TimeOfDay(
          hour: widget.habit!.reminderHour!,
          minute: widget.habit!.reminderMinute!,
        );
      }
      _useTimeVisibility = widget.habit!.useTimeVisibility;
      if (widget.habit!.visibleAfterHour != null &&
          widget.habit!.visibleAfterMinute != null) {
        _visibleAfterTime = TimeOfDay(
          hour: widget.habit!.visibleAfterHour!,
          minute: widget.habit!.visibleAfterMinute!,
        );
      }
    } else {
      _name = '';
      _description = '';
      _importanceScore = 0;
      _startDate = _normalizeDate(DateTime.now());
      _endDate = null;
      if (_environments.isNotEmpty) {
        _selectedEnvironmentIds = {_environments.first.id};
      }
    }
    _nameController = TextEditingController(text: _name);
    _descriptionController = TextEditingController(text: _description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool _hasRuleChanged() {
    final habit = widget.habit;
    if (habit == null) {
      return true;
    }
    return !habit.hasSameRule(
      type: _type,
      frequency: _frequency,
      daysOfWeek: _daysOfWeek,
      timesPerDay: _timesPerDay,
    );
  }

  List<HabitRuleSnapshot> _buildRuleHistory(Habit? habit) {
    final now = DateTime.now();
    final normalizedNow = DateTime(now.year, now.month, now.day);
    if (habit == null) {
      return [
        HabitRuleSnapshot(
          effectiveFrom: _startDate,
          type: _type,
          frequency: _frequency,
          daysOfWeek: _frequency == Frequency.weekly
              ? List<int>.from(_daysOfWeek)
              : null,
          timesPerDay: _type == HabitType.counted ? _timesPerDay : null,
        ),
      ];
    }

    final history = List<HabitRuleSnapshot>.from(habit.ruleHistory);
    if (!_hasRuleChanged()) {
      return history;
    }

    history.add(
      HabitRuleSnapshot(
        effectiveFrom: normalizedNow,
        type: _type,
        frequency: _frequency,
        daysOfWeek: _frequency == Frequency.weekly
            ? List<int>.from(_daysOfWeek)
            : null,
        timesPerDay: _type == HabitType.counted ? _timesPerDay : null,
      ),
    );
    return history;
  }

  Future<void> _saveHabit() async {
    FocusScope.of(context).unfocus();
    _name = _nameController.text.trim();
    _description = _descriptionController.text.trim();
    if (_formKey.currentState!.validate()) {
    _formKey.currentState!.save();
      if (_frequency == Frequency.weekly && _daysOfWeek.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please select at least one day for weekly frequency.',
            ),
          ),
        );
        return;
      }
      if (_reminderEnabled && _reminderTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose a reminder time.')),
        );
        return;
      }
      if (_useTimeVisibility && _visibleAfterTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please choose when the habit becomes visible.'),
          ),
        );
        return;
      }
      if (_endDate != null && _endDate!.isBefore(_startDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('End date cannot be before start date.'),
          ),
        );
        return;
      }
      if (_selectedEnvironmentIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one execution environment.'),
          ),
        );
        return;
      }
      final habitBox = Hive.box(HiveBoxNames.habits);
      int sortOrder = widget.habit?.sortOrder ?? -1;
      if (widget.habit == null) {
        final existingHabits = habitBox.values
            .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        if (existingHabits.isEmpty) {
          sortOrder = 0;
        } else {
          final maxOrder = existingHabits
              .map((habit) => habit.sortOrder)
              .reduce((a, b) => a > b ? a : b);
          sortOrder = maxOrder + 1;
        }
      }
      final newHabit = Habit(
        id: widget.habit?.id ?? const Uuid().v4(),
        name: _name,
        description: _description,
        isImportant: _importanceScore > 0,
        importanceScore: _importanceScore,
        isArchived: widget.habit?.isArchived ?? false,
        type: _type,
        frequency: _frequency,
        executionContext: _legacyExecutionContextForEnvironment(
          _selectedEnvironmentIds.first,
        ),
        environmentIds: _selectedEnvironmentIds.toList(),
        timesPerDay: _timesPerDay,
        timerMinutes: _timerMinutes,
        daysOfWeek: _daysOfWeek,
        startDate: _startDate,
        endDate: _endDate,
        reminderEnabled: _reminderEnabled,
        reminderHour: _reminderTime?.hour,
        reminderMinute: _reminderTime?.minute,
        useTimeVisibility: _useTimeVisibility,
        visibleAfterHour: _useTimeVisibility ? _visibleAfterTime?.hour : null,
        visibleAfterMinute: _useTimeVisibility
            ? _visibleAfterTime?.minute
            : null,
        color: _color,
        priorityLevel: _priorityLevel,
        createdAt: widget.habit?.createdAt ?? DateTime.now(),
        archivedAt: widget.habit?.archivedAt,
        sortOrder: sortOrder,
        ruleHistory: _buildRuleHistory(widget.habit),
      );
      await habitBox.put(newHabit.id, newHabit.toMap());
      final onHabitSaved = widget.onHabitSaved;
      if (onHabitSaved != null) {
        await onHabitSaved(newHabit);
      } else {
        await ReminderService.instance.syncHabitReminder(newHabit);
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    }
  }

  ExecutionContext _legacyExecutionContextForEnvironment(String environmentId) {
    switch (environmentId) {
      case 'deepWork':
        return ExecutionContext.deepWork;
      case 'college':
        return ExecutionContext.college;
      case 'quickTask':
      default:
        return ExecutionContext.quickTask;
    }
  }

  Future<void> _openEnvironmentManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ManageEnvironmentsScreen()),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _environments = loadExecutionEnvironments(_settingsBox);
      _selectedEnvironmentIds.removeWhere(
        (id) => findExecutionEnvironment(_environments, id) == null,
      );
      if (_selectedEnvironmentIds.isEmpty && _environments.isNotEmpty) {
        _selectedEnvironmentIds = {_environments.first.id};
      }
    });
  }

  Future<void> _deleteHabit() async {
    final habitBox = Hive.box(HiveBoxNames.habits);
    await habitBox.delete(widget.habit!.id);
    final onHabitDeleted = widget.onHabitDeleted;
    if (onHabitDeleted != null) {
      await onHabitDeleted(widget.habit!.id);
    } else {
      await ReminderService.instance.cancelHabitReminders(widget.habit!.id);
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        _startDate = _normalizeDate(picked);
        if (_endDate != null && _endDate!.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        _endDate = _normalizeDate(picked);
      });
    }
  }

  void _clearEndDate() {
    setState(() {
      _endDate = null;
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

  Future<void> _pickVisibleAfterTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _visibleAfterTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _visibleAfterTime = picked;
      });
    }
  }

  void _openColorPicker() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pick a color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: _color,
              onColorChanged: (color) {
                setState(() {
                  _color = color;
                });
              },
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 12),
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.habit == null ? 'Add Habit' : 'Edit Habit'),
        actions: [
          if (widget.habit != null)
            IconButton(icon: const Icon(Icons.delete), onPressed: _deleteHabit),
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
                _buildSectionCard(
                  title: 'Basics',
                  icon: Icons.edit_note,
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
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Color',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: _openColorPicker,
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: _color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                'Tap to pick a color',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                _buildSectionCard(
                  title: 'Priority & Context',
                  icon: Icons.flag_outlined,
                  children: [
                    DropdownButtonFormField<PriorityLevel>(
                      initialValue: _priorityLevel,
                      decoration: const InputDecoration(
                        labelText: 'Priority Level',
                        border: OutlineInputBorder(),
                        helperText:
                            'Strategic importance. This stays visible even if the context changes.',
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
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Execution Environments',
                        border: OutlineInputBorder(),
                        helperText:
                            'Where this habit is realistically executable. Select one or more.',
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
                                  _selectedEnvironmentIds.remove(
                                    environment.id,
                                  );
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _openEnvironmentManager,
                        icon: const Icon(Icons.tune),
                        label: const Text('Manage environments'),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Important'),
                      value: _isImportant,
                      onChanged: (value) {
                        setState(() {
                          _isImportant = value;
                          if (!value && _importanceScore > 0) {
                            _importanceScore = 0;
                          }
                          if (value && _importanceScore == 0) {
                            _importanceScore = 1;
                          }
                        });
                      },
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Importance Score: $_importanceScore / 5'),
                        Slider(
                          value: _importanceScore.toDouble(),
                          min: 0,
                          max: 5,
                          divisions: 5,
                          label: _importanceScore.toString(),
                          onChanged: (value) {
                            setState(() {
                              _importanceScore = value.round();
                              _isImportant = _importanceScore > 0;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                _buildSectionCard(
                  title: 'Schedule',
                  icon: Icons.event_repeat,
                  children: [
                    DropdownButtonFormField<HabitType>(
                      initialValue: _type,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                      ),
                      items: HabitType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.toString().split('.').last),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _type = value!;
                        });
                      },
                    ),
                    if (_type == HabitType.counted)
                      TextFormField(
                        initialValue: _timesPerDay?.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Times per Day',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              int.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                        onSaved: (value) =>
                            _timesPerDay = value != null && value.isNotEmpty
                            ? int.parse(value)
                            : null,
                      ),
                    DropdownButtonFormField<Frequency>(
                      initialValue: _frequency,
                      decoration: const InputDecoration(
                        labelText: 'Frequency',
                        border: OutlineInputBorder(),
                      ),
                      items: Frequency.values.map((frequency) {
                        return DropdownMenuItem(
                          value: frequency,
                          child: Text(_frequencyLabel(frequency)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _frequency = value!;
                        });
                      },
                    ),
                    if (_frequency == Frequency.weekly)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Days of the Week'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8.0,
                            children: List<Widget>.generate(7, (int index) {
                              return FilterChip(
                                label: Text(
                                  ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                                ),
                                selected: _daysOfWeek.contains(index + 1),
                                onSelected: (bool selected) {
                                  setState(() {
                                    if (selected) {
                                      _daysOfWeek.add(index + 1);
                                    } else {
                                      _daysOfWeek.remove(index + 1);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Start date'),
                      subtitle: Text(_formatDate(_startDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: _pickStartDate,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('End date'),
                      subtitle: Text(
                        _endDate == null
                            ? 'No end date'
                            : _formatDate(_endDate!),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_endDate != null)
                            IconButton(
                              tooltip: 'Clear end date',
                              icon: const Icon(Icons.clear),
                              onPressed: _clearEndDate,
                            ),
                          const Icon(Icons.calendar_today),
                        ],
                      ),
                      onTap: _pickEndDate,
                    ),
                  ],
                ),
                _buildSectionCard(
                  title: 'Reminders & Extras',
                  icon: Icons.notifications_active_outlined,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Time-based visibility'),
                          subtitle: Text(
                            _useTimeVisibility
                                ? (_visibleAfterTime == null
                                      ? 'Choose when this habit should appear'
                                      : 'Show only after ${_visibleAfterTime!.format(context)}')
                                : 'Always show this habit',
                          ),
                          value: _useTimeVisibility,
                          onChanged: (value) {
                            setState(() {
                              _useTimeVisibility = value;
                              if (!value) {
                                _visibleAfterTime = null;
                              }
                            });
                          },
                        ),
                        if (_useTimeVisibility)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Visible after'),
                            subtitle: Text(
                              _visibleAfterTime?.format(context) ?? 'Not set',
                            ),
                            trailing: const Icon(Icons.schedule),
                            onTap: _pickVisibleAfterTime,
                          ),
                      ],
                    ),
                    TextFormField(
                      initialValue: _timerMinutes?.toString() ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Time required (minutes, optional)',
                        border: OutlineInputBorder(),
                        helperText:
                            'How long this habit takes per day. Powers the habit timer '
                            'and the Weekly Time Budget page.',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return null;
                        }
                        final parsed = int.tryParse(value.trim());
                        if (parsed == null || parsed <= 0) {
                          return 'Please enter a number greater than 0';
                        }
                        return null;
                      },
                      onSaved: (value) {
                        if (value == null || value.trim().isEmpty) {
                          _timerMinutes = null;
                          return;
                        }
                        _timerMinutes = int.tryParse(value.trim());
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saveHabit,
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
