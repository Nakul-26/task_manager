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
  String _searchQuery = '';

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
      activeHabits.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      setState(() {
        _activeHabits = activeHabits;
      });
    }
  }

  List<Habit> get _filteredHabits {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _activeHabits;
    }
    return _activeHabits.where((habit) {
      return habit.name.toLowerCase().contains(query) ||
          habit.description.toLowerCase().contains(query) ||
          habit.environmentId.toLowerCase().contains(query);
    }).toList();
  }

  // Hive notifies the box listener synchronously on every put(), which
  // would otherwise re-enter _loadHabits (and its setState) while we're
  // still in the middle of a bulk write, causing crashes/hangs. Silence
  // the listener for the duration of any multi-put operation.
  void _withoutBoxListener(void Function() action) {
    _habitBox.listenable().removeListener(_loadHabits);
    try {
      action();
    } finally {
      _habitBox.listenable().addListener(_loadHabits);
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
      _withoutBoxListener(() {
        for (final habit in habits) {
          _habitBox.put(habit.id, habit.toMap());
        }
      });
    }
  }

  void _persistOrder() {
    _withoutBoxListener(() {
      for (int i = 0; i < _activeHabits.length; i++) {
        _activeHabits[i].sortOrder = i;
        _habitBox.put(_activeHabits[i].id, _activeHabits[i].toMap());
      }
    });
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

  void _moveHabitByOffset(Habit habit, int offset) {
    final currentIndex = _activeHabits.indexWhere((item) => item.id == habit.id);
    if (currentIndex < 0) {
      return;
    }

    final targetIndex = (currentIndex + offset).clamp(
      0,
      _activeHabits.length - 1,
    );
    if (targetIndex == currentIndex) {
      return;
    }

    setState(() {
      final moved = _activeHabits.removeAt(currentIndex);
      _activeHabits.insert(targetIndex, moved);
      _persistOrder();
    });
  }

  Future<void> _moveHabitToPosition(Habit habit) async {
    final currentIndex = _activeHabits.indexWhere((item) => item.id == habit.id);
    if (currentIndex < 0) {
      return;
    }

    final controller = TextEditingController(
      text: (currentIndex + 1).toString(),
    );
    final formKey = GlobalKey<FormState>();
    final requestedPosition = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set habit order'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Order number',
              helperText: 'Enter a number between 1 and ${_activeHabits.length}',
            ),
            validator: (value) {
              final parsed = int.tryParse(value?.trim() ?? '');
              if (parsed == null) {
                return 'Enter a whole number';
              }
              if (parsed < 1 || parsed > _activeHabits.length) {
                return 'Enter a number from 1 to ${_activeHabits.length}';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(
                  int.parse(controller.text.trim()),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (requestedPosition == null) {
      return;
    }

    final targetIndex = requestedPosition - 1;
    if (targetIndex == currentIndex) {
      return;
    }

    setState(() {
      final moved = _activeHabits.removeAt(currentIndex);
      _activeHabits.insert(targetIndex, moved);
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

  void _clearSearch() {
    if (_searchQuery.isEmpty) {
      return;
    }
    setState(() {
      _searchQuery = '';
    });
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
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.save_alt),
                    title: const Text('Export File'),
                    subtitle: const Text(
                      'Save a JSON backup to your Downloads folder',
                    ),
                    onTap: () => Navigator.of(sheetContext).pop(
                      _HabitsExportAction.exportFile,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.ios_share),
                    title: const Text('Share Backup'),
                    subtitle: const Text(
                      'Open the share sheet with the backup file',
                    ),
                    onTap: () => Navigator.of(sheetContext).pop(
                      _HabitsExportAction.shareFile,
                    ),
                  ),
                ],
              ),
            ),
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
    final currentIndex = _activeHabits.indexWhere((item) => item.id == habit.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: SingleChildScrollView(
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
                    leading: const Icon(Icons.vertical_align_top),
                    title: const Text('Move to top'),
                    enabled: currentIndex > 0,
                    onTap: () {
                      Navigator.of(context).pop();
                      _moveHabitByOffset(habit, -_activeHabits.length);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: const Text('Move up'),
                    enabled: currentIndex > 0,
                    onTap: () {
                      Navigator.of(context).pop();
                      _moveHabitByOffset(habit, -1);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.arrow_downward),
                    title: const Text('Move down'),
                    enabled:
                        currentIndex >= 0 &&
                        currentIndex < _activeHabits.length - 1,
                    onTap: () {
                      Navigator.of(context).pop();
                      _moveHabitByOffset(habit, 1);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.vertical_align_bottom),
                    title: const Text('Move to bottom'),
                    enabled:
                        currentIndex >= 0 &&
                        currentIndex < _activeHabits.length - 1,
                    onTap: () {
                      Navigator.of(context).pop();
                      _moveHabitByOffset(habit, _activeHabits.length);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.pin_outlined),
                    title: const Text('Set exact order'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _moveHabitToPosition(habit);
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
            ),
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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Search habits',
                      hintText: 'Name, description, or environment',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_searchQuery.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_filteredHabits.length} result${_filteredHabits.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: _searchQuery.trim().isEmpty
                      ? ReorderableListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          buildDefaultDragHandles: false,
                          onReorder: _onReorder,
                          itemCount: _activeHabits.length,
                          itemBuilder: (context, index) {
                            final habit = _activeHabits[index];
                            return _buildHabitTile(
                              habit: habit,
                              displayIndex: index + 1,
                              draggable: true,
                              reorderIndex: index,
                            );
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: _filteredHabits.length,
                          itemBuilder: (context, index) {
                            final habit = _filteredHabits[index];
                            final fullIndex = _activeHabits.indexWhere(
                              (item) => item.id == habit.id,
                            );
                            return _buildHabitTile(
                              habit: habit,
                              displayIndex: fullIndex + 1,
                              draggable: false,
                              reorderIndex: null,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildHabitTile({
    required Habit habit,
    required int displayIndex,
    required bool draggable,
    required int? reorderIndex,
  }) {
    return ListTile(
      key: ValueKey(habit.id),
      isThreeLine: habit.description.trim().isNotEmpty,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      leading: SizedBox(
        width: 72,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OrderBadge(number: displayIndex),
            const SizedBox(width: 8),
            if (draggable && reorderIndex != null)
              ReorderableDragStartListener(
                index: reorderIndex,
                child: const Icon(Icons.drag_handle),
              )
            else
              const Icon(Icons.drag_handle, color: Colors.transparent),
          ],
        ),
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
  }
}

enum _HabitsExportAction { exportFile, shareFile }

class _OrderBadge extends StatelessWidget {
  final int number;

  const _OrderBadge({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Text(
        number.toString(),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontSize: 12,
        ),
      ),
    );
  }
}
