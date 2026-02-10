import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';

class AddEditHabitScreen extends StatefulWidget {
  final Habit? habit;

  const AddEditHabitScreen({super.key, this.habit});

  @override
  State<AddEditHabitScreen> createState() => _AddEditHabitScreenState();
}

class _AddEditHabitScreenState extends State<AddEditHabitScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _description;
  HabitType _type = HabitType.binary;
  Frequency _frequency = Frequency.daily;
  int? _timesPerDay;
  List<int> _daysOfWeek = [];
  Color _color = Colors.blue;
  bool _isImportant = false;
  bool _reminderEnabled = false;
  TimeOfDay? _reminderTime;

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
    if (widget.habit != null) {
      _name = widget.habit!.name;
      _description = widget.habit!.description;
      _type = widget.habit!.type;
      _frequency = widget.habit!.frequency;
      _timesPerDay = widget.habit!.timesPerDay;
      _daysOfWeek = widget.habit!.daysOfWeek ?? [];
      _color = widget.habit!.color;
      _isImportant = widget.habit!.isImportant;
      _reminderEnabled = widget.habit!.reminderEnabled;
      if (widget.habit!.reminderHour != null &&
          widget.habit!.reminderMinute != null) {
        _reminderTime = TimeOfDay(
          hour: widget.habit!.reminderHour!,
          minute: widget.habit!.reminderMinute!,
        );
      }
    } else {
      _name = '';
      _description = '';
    }
  }

  Future<void> _saveHabit() async {
    if (_formKey.currentState!.validate()) {
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

      _formKey.currentState!.save();
      final habitBox = Hive.box('habits');
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
        isImportant: _isImportant,
        isArchived: widget.habit?.isArchived ?? false,
        type: _type,
        frequency: _frequency,
        timesPerDay: _timesPerDay,
        daysOfWeek: _daysOfWeek,
        reminderEnabled: _reminderEnabled,
        reminderHour: _reminderTime?.hour,
        reminderMinute: _reminderTime?.minute,
        color: _color,
        createdAt: widget.habit?.createdAt ?? DateTime.now(),
        archivedAt: widget.habit?.archivedAt,
        sortOrder: sortOrder,
      );
      habitBox.put(newHabit.id, newHabit.toMap());
      await ReminderService.instance.syncHabitReminder(newHabit);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    }
  }

  Future<void> _deleteHabit() async {
    final habitBox = Hive.box('habits');
    await habitBox.delete(widget.habit!.id);
    await ReminderService.instance.cancelHabitReminders(widget.habit!.id);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
                onSaved: (value) => _name = value!,
              ),
              TextFormField(
                initialValue: _description,
                decoration: const InputDecoration(labelText: 'Description'),
                onSaved: (value) => _description = value ?? '',
              ),
              SwitchListTile(
                title: const Text('Important'),
                value: _isImportant,
                onChanged: (value) {
                  setState(() {
                    _isImportant = value;
                  });
                },
              ),
              DropdownButtonFormField<HabitType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
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
                  decoration: const InputDecoration(labelText: 'Times per Day'),
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
                decoration: const InputDecoration(labelText: 'Frequency'),
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
              if (_frequency == Frequency.weekly) ...[
                const SizedBox(height: 16),
                const Text('Days of the Week'),
                Wrap(
                  spacing: 8.0,
                  children: List<Widget>.generate(7, (int index) {
                    return FilterChip(
                      label: Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][index]),
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
              const SizedBox(height: 16),
              SwitchListTile(
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
                  subtitle: Text(_reminderTime?.format(context) ?? 'Not set'),
                  trailing: const Icon(Icons.schedule),
                  onTap: _pickReminderTime,
                ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _openColorPicker,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'Pick a color',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _saveHabit, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}
