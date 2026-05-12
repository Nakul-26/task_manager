import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:habit_tracker/add_edit_habit_screen.dart';
import 'package:habit_tracker/archived_habits_screen.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
    _habitBox = Hive.box(HiveBoxNames.habits);
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
      activeHabits.sort((a, b) {
        final scoreCompare = b.importanceScore.compareTo(a.importanceScore);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return a.sortOrder.compareTo(b.sortOrder);
      });
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

  void _openAddHabit() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (context) => const AddEditHabitScreen()),
        )
        .then((_) => _loadHabits());
  }

  Map<String, dynamic> _buildHabitsExportPayload() {
    final habits = _habitBox.values
        .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) {
        final archivedCompare = a.isArchived == b.isArchived
            ? 0
            : (a.isArchived ? 1 : -1);
        if (archivedCompare != 0) {
          return archivedCompare;
        }
        final importanceCompare = b.importanceScore.compareTo(a.importanceScore);
        if (importanceCompare != 0) {
          return importanceCompare;
        }
        return a.sortOrder.compareTo(b.sortOrder);
      });

    return {
      'appVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'habitCount': habits.length,
      'habits': habits.map((habit) => habit.toExportMap()).toList(),
    };
  }

  String _buildHabitsExportJson() {
    return jsonEncode(_buildHabitsExportPayload());
  }

  String _buildExportFileName() {
    final now = DateTime.now();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}_'
        '${now.month.toString().padLeft(2, '0')}_'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'habits_backup_$timestamp.json';
  }

  Future<Directory> _resolveExportDirectory() async {
    final downloadsDirectory = await getDownloadsDirectory();
    if (downloadsDirectory != null) {
      return downloadsDirectory;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<File> _writeHabitsExportFile() async {
    final directory = await _resolveExportDirectory();
    await directory.create(recursive: true);
    final exportFile = File('${directory.path}${Platform.pathSeparator}${_buildExportFileName()}');
    await exportFile.writeAsString(_buildHabitsExportJson());
    return exportFile;
  }

  Future<File> _createSharedExportFile() async {
    final tempDirectory = await Directory.systemTemp.createTemp('habit_backup_');
    final exportFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}${_buildExportFileName()}',
    );
    await exportFile.writeAsString(_buildHabitsExportJson());
    return exportFile;
  }

  Future<void> _exportHabitsToFile() async {
    final exportFile = await _writeHabitsExportFile();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Backup exported to ${exportFile.path}.'),
      ),
    );
  }

  Future<void> _shareHabitsExport() async {
    final exportFile = await _createSharedExportFile();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(exportFile.path)],
        title: 'Habits backup',
        subject: 'Habits backup',
      ),
    );
  }

  Future<void> _showExportActions() async {
    final action = await showModalBottomSheet<_HabitsExportAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Export File'),
                subtitle: const Text('Save a JSON backup to your Downloads folder'),
                onTap: () => Navigator.of(sheetContext).pop(
                  _HabitsExportAction.exportFile,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Share Backup'),
                subtitle: const Text('Open the share sheet with the backup file'),
                onTap: () => Navigator.of(sheetContext).pop(
                  _HabitsExportAction.shareFile,
                ),
              ),
            ],
          ),
        );
      },
    );

    switch (action) {
      case _HabitsExportAction.exportFile:
        await _exportHabitsToFile();
        break;
      case _HabitsExportAction.shareFile:
        await _shareHabitsExport();
        break;
      case null:
        break;
    }
  }

  void _openEditHabit(Habit habit) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => AddEditHabitScreen(habit: habit),
          ),
        )
        .then((_) => _loadHabits());
  }

  void _showHabitActions(BuildContext context, Habit habit) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.of(context).pop();
                  _openEditHabit(habit);
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Archive'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _setArchiveStatus(habit, true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.of(context).pop();
                  _deleteHabit(habit);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Habits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export Backup',
            onPressed: _showExportActions,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Habit',
            onPressed: _openAddHabit,
          ),
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
              padding: const EdgeInsets.only(bottom: 16),
              buildDefaultDragHandles: false,
              onReorder: _onReorder,
              itemCount: _activeHabits.length,
              itemBuilder: (context, index) {
                final habit = _activeHabits[index];
                return ListTile(
                  key: ValueKey(habit.id),
                  isThreeLine: habit.description.trim().isNotEmpty,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                  title: Text(
                    habit.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: habit.description.trim().isEmpty
                      ? null
                      : Text(
                          habit.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Habit actions',
                    onPressed: () => _showHabitActions(context, habit),
                  ),
                );
              },
            ),
    );
  }
}

enum _HabitsExportAction { exportFile, shareFile }
