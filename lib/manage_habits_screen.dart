import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/add_edit_habit_screen.dart';
import 'package:habit_tracker/archived_habits_screen.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:habit_tracker/utils/debounced_callback.dart';
import 'package:habit_tracker/utils/delete_feedback.dart';
import 'package:habit_tracker/utils/execution_environment_utils.dart';
import 'package:habit_tracker/utils/item_move.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum _ImportanceFilter { any, importantOnly, notImportant }

class ManageHabitsScreen extends StatefulWidget {
  const ManageHabitsScreen({super.key});

  @override
  State<ManageHabitsScreen> createState() => _ManageHabitsScreenState();
}

class _ManageHabitsScreenState extends State<ManageHabitsScreen> {
  late Box<dynamic> _habitBox;
  late Box<dynamic> _settingsBox;
  late ValueListenable<Box<dynamic>> _habitListenable;
  late VoidCallback _debouncedLoadHabits;
  List<Habit> _activeHabits = [];
  List<ExecutionEnvironment> _environments = [];
  String _searchQuery = '';
  bool _isSavingOrder = false;

  Set<String> _filterEnvironmentIds = {};
  Set<PriorityLevel> _filterPriorityLevels = {};
  Set<HabitType> _filterHabitTypes = {};
  Set<Frequency> _filterFrequencies = {};
  _ImportanceFilter _filterImportance = _ImportanceFilter.any;

  @override
  void initState() {
    super.initState();
    _habitBox = Hive.box(HiveBoxNames.habits);
    _settingsBox = Hive.box(HiveBoxNames.appSettings);
    _environments = loadExecutionEnvironments(_settingsBox);
    // Box.listenable() returns a NEW wrapper object on every call, so we
    // must cache a single instance here and reuse it for add/removeListener
    // below — otherwise removeListener silently targets an empty wrapper
    // and never actually detaches the original listener.
    _habitListenable = _habitBox.listenable();
    // A bulk write (e.g. persisting a reorder) fires one Hive change event
    // per key. Debounce so a burst of events collapses into a single
    // reload instead of one full rebuild per key.
    _debouncedLoadHabits = debounceMicrotask(_loadHabits);
    _loadHabits();
    _habitListenable.addListener(_debouncedLoadHabits);
  }

  @override
  void dispose() {
    _habitListenable.removeListener(_debouncedLoadHabits);
    super.dispose();
  }

  void _loadHabits() {
    if (mounted) {
      final habits = _habitBox.values
          .map((e) => Habit.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      final activeHabits = habits.where((habit) => !habit.isArchived).toList();
      _ensureSortOrder(activeHabits);
      // Match the Today screen: important habits float to the top
      // regardless of manual order, so the two screens never disagree.
      activeHabits.sort((a, b) {
        final importanceCompare = b.importanceScore.compareTo(
          a.importanceScore,
        );
        if (importanceCompare != 0) {
          return importanceCompare;
        }
        final priorityCompare = a.priorityLevel.index.compareTo(
          b.priorityLevel.index,
        );
        if (priorityCompare != 0) {
          return priorityCompare;
        }
        return a.sortOrder.compareTo(b.sortOrder);
      });
      setState(() {
        _activeHabits = activeHabits;
      });
    }
  }

  bool get _hasActiveFilters =>
      _filterEnvironmentIds.isNotEmpty ||
      _filterPriorityLevels.isNotEmpty ||
      _filterHabitTypes.isNotEmpty ||
      _filterFrequencies.isNotEmpty ||
      _filterImportance != _ImportanceFilter.any;

  int get _activeFilterCount =>
      (_filterEnvironmentIds.isNotEmpty ? 1 : 0) +
      (_filterPriorityLevels.isNotEmpty ? 1 : 0) +
      (_filterHabitTypes.isNotEmpty ? 1 : 0) +
      (_filterFrequencies.isNotEmpty ? 1 : 0) +
      (_filterImportance != _ImportanceFilter.any ? 1 : 0);

  bool _matchesFilters(Habit habit) {
    if (_filterEnvironmentIds.isNotEmpty &&
        !habit.environmentIds.any(_filterEnvironmentIds.contains)) {
      return false;
    }
    if (_filterPriorityLevels.isNotEmpty &&
        !_filterPriorityLevels.contains(habit.priorityLevel)) {
      return false;
    }
    if (_filterHabitTypes.isNotEmpty &&
        !_filterHabitTypes.contains(habit.type)) {
      return false;
    }
    if (_filterFrequencies.isNotEmpty &&
        !_filterFrequencies.contains(habit.frequency)) {
      return false;
    }
    switch (_filterImportance) {
      case _ImportanceFilter.importantOnly:
        if (!habit.isImportant) {
          return false;
        }
        break;
      case _ImportanceFilter.notImportant:
        if (habit.isImportant) {
          return false;
        }
        break;
      case _ImportanceFilter.any:
        break;
    }
    return true;
  }

  List<Habit> get _filteredHabits {
    final query = _searchQuery.trim().toLowerCase();
    return _activeHabits.where((habit) {
      if (!_matchesFilters(habit)) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return habit.name.toLowerCase().contains(query) ||
          habit.description.toLowerCase().contains(query) ||
          habit.environmentIds.any((id) => id.toLowerCase().contains(query));
    }).toList();
  }

  bool get _isBrowsingFiltered =>
      _searchQuery.trim().isNotEmpty || _hasActiveFilters;

  // Hive notifies the box listener synchronously on every put(), which
  // would otherwise re-enter _loadHabits (and its setState) while we're
  // still in the middle of a bulk write, causing crashes/hangs. Silence
  // the listener for the duration of any multi-put operation.
  Future<void> _withoutBoxListener(Future<void> Function() action) async {
    _habitListenable.removeListener(_debouncedLoadHabits);
    try {
      await action();
    } finally {
      _habitListenable.addListener(_debouncedLoadHabits);
    }
  }

  void _ensureSortOrder(List<Habit> habits) {
    final changedHabits = <String, dynamic>{};
    for (int i = 0; i < habits.length; i++) {
      if (habits[i].sortOrder < 0) {
        habits[i].sortOrder = i;
        changedHabits[habits[i].id] = habits[i].toMap();
      }
    }
    if (changedHabits.isNotEmpty) {
      _withoutBoxListener(() => _habitBox.putAll(changedHabits));
    }
  }

  // Moving one habit only ever changes the sortOrder of the habits between
  // its old and new position, not the whole list. Writing all of them on
  // every move (as before) meant a single drag on a 67-habit list appended
  // 67 frames to the Hive file every time, which is what made every reorder
  // hang. Only write the habits whose sortOrder actually changed, and do it
  // as one batched putAll instead of N separate put calls.
  Future<void> _persistOrder() async {
    final changedHabits = <String, dynamic>{};
    for (int i = 0; i < _activeHabits.length; i++) {
      if (_activeHabits[i].sortOrder != i) {
        _activeHabits[i].sortOrder = i;
        changedHabits[_activeHabits[i].id] = _activeHabits[i].toMap();
      }
    }
    if (changedHabits.isEmpty) {
      return;
    }
    await _withoutBoxListener(() => _habitBox.putAll(changedHabits));
  }

  Future<void> _reorderAndPersist(void Function() reorder) async {
    setState(() {
      reorder();
      _isSavingOrder = true;
    });
    await _persistOrder();
    if (mounted) {
      setState(() {
        _isSavingOrder = false;
      });
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    _reorderAndPersist(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final habit = _activeHabits.removeAt(oldIndex);
      _activeHabits.insert(newIndex, habit);
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

    _reorderAndPersist(() {
      final moved = _activeHabits.removeAt(currentIndex);
      _activeHabits.insert(targetIndex, moved);
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

    await _reorderAndPersist(() {
      final moved = _activeHabits.removeAt(currentIndex);
      _activeHabits.insert(targetIndex, moved);
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
              final removedMap = Map<String, dynamic>.from(habit.toMap());
              await _habitBox.delete(habit.id);
              await ReminderService.instance.cancelHabitReminders(habit.id);
              if (!context.mounted) {
                return;
              }
              Navigator.of(context).pop();
              if (!mounted) {
                return;
              }
              showUndoSnackBar(
                this.context,
                message: 'Deleted "${habit.name}"',
                onUndo: () async {
                  await _habitBox.put(habit.id, removedMap);
                  await ReminderService.instance.syncHabitReminder(
                    Habit.fromMap(removedMap),
                  );
                },
              );
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

  String _priorityLevelLabel(PriorityLevel level) {
    switch (level) {
      case PriorityLevel.core:
        return 'Core';
      case PriorityLevel.secondary:
        return 'Secondary';
      case PriorityLevel.optional:
        return 'Optional';
    }
  }

  String _habitTypeLabel(HabitType type) {
    switch (type) {
      case HabitType.binary:
        return 'Binary (yes/no)';
      case HabitType.counted:
        return 'Counted';
    }
  }

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

  Future<void> _showFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void toggleEnvironment(String id) {
              setSheetState(() {
                if (!_filterEnvironmentIds.add(id)) {
                  _filterEnvironmentIds.remove(id);
                }
              });
            }

            void togglePriority(PriorityLevel level) {
              setSheetState(() {
                if (!_filterPriorityLevels.add(level)) {
                  _filterPriorityLevels.remove(level);
                }
              });
            }

            void toggleType(HabitType type) {
              setSheetState(() {
                if (!_filterHabitTypes.add(type)) {
                  _filterHabitTypes.remove(type);
                }
              });
            }

            void toggleFrequency(Frequency frequency) {
              setSheetState(() {
                if (!_filterFrequencies.add(frequency)) {
                  _filterFrequencies.remove(frequency);
                }
              });
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Filter Habits',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_hasActiveFilters)
                            TextButton(
                              onPressed: () {
                                setSheetState(() {
                                  _filterEnvironmentIds = {};
                                  _filterPriorityLevels = {};
                                  _filterHabitTypes = {};
                                  _filterFrequencies = {};
                                  _filterImportance = _ImportanceFilter.any;
                                });
                              },
                              child: const Text('Clear all'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Importance',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Any'),
                            selected:
                                _filterImportance == _ImportanceFilter.any,
                            onSelected: (_) => setSheetState(
                              () =>
                                  _filterImportance = _ImportanceFilter.any,
                            ),
                          ),
                          ChoiceChip(
                            label: const Text('Important only'),
                            selected:
                                _filterImportance ==
                                _ImportanceFilter.importantOnly,
                            onSelected: (_) => setSheetState(
                              () => _filterImportance =
                                  _ImportanceFilter.importantOnly,
                            ),
                          ),
                          ChoiceChip(
                            label: const Text('Not important'),
                            selected:
                                _filterImportance ==
                                _ImportanceFilter.notImportant,
                            onSelected: (_) => setSheetState(
                              () => _filterImportance =
                                  _ImportanceFilter.notImportant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Priority level',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: PriorityLevel.values.map((level) {
                          return FilterChip(
                            label: Text(_priorityLevelLabel(level)),
                            selected: _filterPriorityLevels.contains(level),
                            onSelected: (_) => togglePriority(level),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Type',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: HabitType.values.map((type) {
                          return FilterChip(
                            label: Text(_habitTypeLabel(type)),
                            selected: _filterHabitTypes.contains(type),
                            onSelected: (_) => toggleType(type),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Frequency',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: Frequency.values.map((frequency) {
                          return FilterChip(
                            label: Text(_frequencyLabel(frequency)),
                            selected: _filterFrequencies.contains(frequency),
                            onSelected: (_) => toggleFrequency(frequency),
                          );
                        }).toList(),
                      ),
                      if (_environments.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Environment',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: _environments.map((environment) {
                            return FilterChip(
                              label: Text(environment.name),
                              selected: _filterEnvironmentIds.contains(
                                environment.id,
                              ),
                              onSelected: (_) =>
                                  toggleEnvironment(environment.id),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) {
      setState(() {});
    }
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

  String _buildHabitNamesText() {
    final payload = _buildHabitsExportPayload();
    final habits = payload['habits'] as List;
    return habits.map((habit) => (habit as Map)['name'] as String).join('\n');
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

  String _buildNamesExportFileName() {
    final now = DateTime.now();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}_'
        '${now.month.toString().padLeft(2, '0')}_'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'habit_names_$timestamp.txt';
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

  Future<File> _writeHabitNamesExportFile() async {
    final directory = await _resolveExportDirectory();
    await directory.create(recursive: true);
    final exportFile = File(
      '${directory.path}${Platform.pathSeparator}${_buildNamesExportFileName()}',
    );
    await exportFile.writeAsString(_buildHabitNamesText());
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

  Future<void> _exportHabitNamesToFile() async {
    final exportFile = await _writeHabitNamesExportFile();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Habit names exported to ${exportFile.path}.'),
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
                  ListTile(
                    leading: const Icon(Icons.short_text),
                    title: const Text('Export Names Only'),
                    subtitle: const Text(
                      'Save a plain text list of habit names, nothing else',
                    ),
                    onTap: () => Navigator.of(sheetContext).pop(
                      _HabitsExportAction.exportNamesOnly,
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
      case _HabitsExportAction.exportNamesOnly:
        await _exportHabitNamesToFile();
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
                    leading: const Icon(Icons.swap_horiz),
                    title: const Text('Move to...'),
                    subtitle: const Text('Turn into a task, reminder, or note'),
                    onTap: () {
                      Navigator.of(context).pop();
                      showMoveToSheet(
                        context: this.context,
                        sourceKind: ItemKind.habit,
                        sourceItem: habit,
                      );
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
            icon: Badge(
              isLabelVisible: _activeFilterCount > 0,
              label: Text('$_activeFilterCount'),
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filter habits',
            onPressed: _showFilterSheet,
          ),
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
                if (_isSavingOrder) const LinearProgressIndicator(minHeight: 3),
                if (_isBrowsingFiltered)
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
                  child: !_isBrowsingFiltered
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

enum _HabitsExportAction { exportFile, shareFile, exportNamesOnly }

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
