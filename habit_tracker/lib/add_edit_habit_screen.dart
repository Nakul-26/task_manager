import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:habit_tracker/models.dart';
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
  Color _color = Colors.blue;
  bool _isImportant = false;

  @override
  void initState() {
    super.initState();
    if (widget.habit != null) {
      _name = widget.habit!.name;
      _description = widget.habit!.description;
      _type = widget.habit!.type;
      _frequency = widget.habit!.frequency;
      _timesPerDay = widget.habit!.timesPerDay;
      _color = widget.habit!.color;
      _isImportant = widget.habit!.isImportant;
    } else {
      _name = '';
      _description = '';
    }
  }

  void _saveHabit() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final habitBox = Hive.box('habits');
      final newHabit = Habit(
        id: widget.habit?.id ?? const Uuid().v4(),
        name: _name,
        description: _description,
        isImportant: _isImportant,
        type: _type,
        frequency: _frequency,
        timesPerDay: _timesPerDay,
        color: _color,
        createdAt: widget.habit?.createdAt ?? DateTime.now(),
      );
      habitBox.put(newHabit.id, newHabit.toMap());
      Navigator.of(context).pop();
    }
  }

  void _deleteHabit() {
    final habitBox = Hive.box('habits');
    habitBox.delete(widget.habit!.id);
    Navigator.of(context).pop();
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
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteHabit,
            ),
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
                value: _type,
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
                    if (value != null && value.isNotEmpty && int.tryParse(value) == null) {
                      return 'Please enter a valid number';
                    }
                    return null;
                  },
                  onSaved: (value) => _timesPerDay = value != null && value.isNotEmpty ? int.parse(value) : null,
                ),
              DropdownButtonFormField<Frequency>(
                value: _frequency,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: Frequency.values.map((frequency) {
                  return DropdownMenuItem(
                    value: frequency,
                    child: Text(frequency.toString().split('.').last),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _frequency = value!;
                  });
                },
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
              ElevatedButton(
                onPressed: _saveHabit,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
