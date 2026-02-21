import 'package:flutter/material.dart';
import 'package:habit_tracker/add_edit_habit_screen.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ArchivedHabitsScreen extends StatefulWidget {
  const ArchivedHabitsScreen({super.key});

  @override
  State<ArchivedHabitsScreen> createState() => _ArchivedHabitsScreenState();
}

class _ArchivedHabitsScreenState extends State<ArchivedHabitsScreen> {
  late Box<dynamic> _habitBox;
  List<Habit> _archivedHabits = [];

  @override
  void initState() {
    super.initState();
    _habitBox = Hive.box('habits');
    _loadArchivedHabits();
    _habitBox.listenable().addListener(_loadArchivedHabits);
  }

  @override
  void dispose() {
    _habitBox.listenable().removeListener(_loadArchivedHabits);
    super.dispose();
  }

  void _loadArchivedHabits() {
    if (!mounted) {
      return;
    }

    final archivedHabits =
        _habitBox.values
            .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
            .where((habit) => habit.isArchived)
            .toList()
          ..sort((a, b) {
            final aDate =
                a.archivedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                b.archivedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

    setState(() {
      _archivedHabits = archivedHabits;
    });
  }

  Future<void> _setArchiveStatus(Habit habit, bool isArchived) async {
    habit.isArchived = isArchived;
    habit.archivedAt = isArchived ? DateTime.now() : null;
    if (!isArchived) {
      final activeHabits = _habitBox.values
          .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
          .where((h) => !h.isArchived)
          .toList();
      final maxOrder = activeHabits.isEmpty
          ? -1
          : activeHabits
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
      appBar: AppBar(title: const Text('Archived Habits')),
      body: _archivedHabits.isEmpty
          ? const Center(child: Text('No archived habits.'))
          : ListView.builder(
              itemCount: _archivedHabits.length,
              itemBuilder: (context, index) {
                final habit = _archivedHabits[index];
                return ListTile(
                  leading: const Icon(Icons.archive),
                  title: Text(
                    habit.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    habit.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.unarchive_outlined),
                        tooltip: 'Unarchive',
                        onPressed: () => _setArchiveStatus(habit, false),
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
                              .then((_) => _loadArchivedHabits());
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
    );
  }
}
