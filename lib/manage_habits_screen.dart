import 'package:flutter/material.dart';
import 'package:habit_tracker/add_edit_habit_screen.dart';
import 'package:habit_tracker/archived_habits_screen.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ManageHabitsScreen extends StatefulWidget {
  const ManageHabitsScreen({super.key});

  @override
  State<ManageHabitsScreen> createState() => _ManageHabitsScreenState();
}

class _ManageHabitsScreenState extends State<ManageHabitsScreen> {
  late Box<dynamic> _habitBox;
  List<Habit> _activeHabits = [];

  @override
  void initState() {
    super.initState();
    _habitBox = Hive.box('habits');
    _loadHabits();
    _habitBox.listenable().addListener(_loadHabits);
  }

  @override
  void dispose() {
    _habitBox.listenable().removeListener(_loadHabits);
    super.dispose();
  }

  void _loadHabits() {
    if (mounted) {
      final habits = _habitBox.values
          .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      final activeHabits = habits.where((habit) => !habit.isArchived).toList();
      _ensureSortOrder(activeHabits);
      activeHabits.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      setState(() {
        _activeHabits = activeHabits;
      });
    }
  }

  void _ensureSortOrder(List<Habit> habits) {
    bool needsSave = false;
    for (int i = 0; i < habits.length; i++) {
      if (habits[i].sortOrder < 0) {
        habits[i].sortOrder = i;
        needsSave = true;
      }
    }
    if (needsSave) {
      for (final habit in habits) {
        _habitBox.put(habit.id, habit.toMap());
      }
    }
  }

  void _persistOrder() {
    for (int i = 0; i < _activeHabits.length; i++) {
      _activeHabits[i].sortOrder = i;
      _habitBox.put(_activeHabits[i].id, _activeHabits[i].toMap());
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final habit = _activeHabits.removeAt(oldIndex);
      _activeHabits.insert(newIndex, habit);
      _persistOrder();
    });
  }

  Future<void> _setArchiveStatus(Habit habit, bool isArchived) async {
    habit.isArchived = isArchived;
    habit.archivedAt = isArchived ? DateTime.now() : null;
    if (!isArchived) {
      final maxOrder = _activeHabits.isEmpty
          ? -1
          : _activeHabits
                .map((h) => h.sortOrder)
                .reduce((a, b) => a > b ? a : b);
      habit.sortOrder = maxOrder + 1;
    }
    await _habitBox.put(habit.id, habit.toMap());
    await ReminderService.instance.syncHabitReminder(habit);
  }

  void _deleteHabit(Habit habit) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Habit'),
        content: Text('Are you sure you want to delete "${habit.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _habitBox.delete(habit.id);
              await ReminderService.instance.cancelHabitReminders(habit.id);
              if (!context.mounted) {
                return;
              }
              Navigator.of(context).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Habits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Archived Habits',
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (context) => const ArchivedHabitsScreen(),
                    ),
                  )
                  .then((_) => _loadHabits());
            },
          ),
        ],
      ),
      body: _activeHabits.isEmpty
          ? const Center(child: Text('No habits yet.'))
          : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              onReorder: _onReorder,
              itemCount: _activeHabits.length,
              itemBuilder: (context, index) {
                final habit = _activeHabits[index];
                return ListTile(
                  key: ValueKey(habit.id),
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                  title: Text(habit.name),
                  subtitle: Text(habit.description),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.archive_outlined),
                        tooltip: 'Archive',
                        onPressed: () => _setArchiveStatus(habit, true),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      AddEditHabitScreen(habit: habit),
                                ),
                              )
                              .then((_) => _loadHabits());
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteHabit(habit),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (context) => const AddEditHabitScreen(),
                ),
              )
              .then((_) => _loadHabits());
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
