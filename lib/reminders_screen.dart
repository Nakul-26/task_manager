import 'package:flutter/material.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:habit_tracker/utils/delete_feedback.dart';
import 'package:habit_tracker/utils/item_move.dart';
import 'package:habit_tracker/widgets/list_section_header.dart';
import 'package:habit_tracker/widgets/move_hint_banner.dart';
import 'package:habit_tracker/widgets/move_or_delete_dismissible.dart';
import 'package:habit_tracker/widgets/type_app_bar.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late Box<dynamic> _reminderBox;
  late Box<dynamic> _settingsBox;
  late bool _showMoveHint;

  @override
  void initState() {
    super.initState();
    _reminderBox = Hive.box(HiveBoxNames.reminders);
    _settingsBox = Hive.box(HiveBoxNames.appSettings);
    _showMoveHint = !hasSeenMoveHint(_settingsBox);
  }

  Future<void> _dismissMoveHint() async {
    await markMoveHintSeen(_settingsBox);
    if (mounted) {
      setState(() {
        _showMoveHint = false;
      });
    }
  }

  List<Reminder> _loadReminders() {
    return _reminderBox.values
        .map((e) => Reminder.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _toggleCompleted(Reminder reminder) async {
    reminder.isCompleted = !reminder.isCompleted;
    await _reminderBox.put(reminder.id, reminder.toMap());
    await ReminderService.instance.syncReminder(reminder);
    setState(() {});
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    final removedMap = Map<String, dynamic>.from(reminder.toMap());
    await _reminderBox.delete(reminder.id);
    await ReminderService.instance.cancelReminder(reminder.id);
    if (!mounted) {
      return;
    }
    setState(() {});
    showUndoSnackBar(
      context,
      message: 'Deleted "${reminder.title}"',
      onUndo: () async {
        await _reminderBox.put(reminder.id, removedMap);
        await ReminderService.instance.syncReminder(
          Reminder.fromMap(removedMap),
        );
      },
    );
  }

  Future<void> _openReminderSheet([Reminder? reminder]) async {
    final titleController = TextEditingController(text: reminder?.title ?? '');
    final noteController = TextEditingController(text: reminder?.note ?? '');
    DateTime dateTime = reminder?.dateTime ?? DateTime.now().add(
      const Duration(hours: 1),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      reminder == null ? 'New Reminder' : 'Edit Reminder',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: reminder == null,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date & time'),
                      subtitle: Text(
                        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
                        '${TimeOfDay.fromDateTime(dateTime).format(sheetContext)}',
                      ),
                      trailing: const Icon(Icons.schedule),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: sheetContext,
                          initialDate: dateTime,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (pickedDate == null || !sheetContext.mounted) {
                          return;
                        }
                        final pickedTime = await showTimePicker(
                          context: sheetContext,
                          initialTime: TimeOfDay.fromDateTime(dateTime),
                        );
                        if (pickedTime == null) {
                          return;
                        }
                        setSheetState(() {
                          dateTime = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            pickedTime.hour,
                            pickedTime.minute,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        final title = titleController.text.trim();
                        if (title.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a title.'),
                            ),
                          );
                          return;
                        }
                        final newReminder = Reminder(
                          id: reminder?.id ?? const Uuid().v4(),
                          title: title,
                          note: noteController.text.trim(),
                          dateTime: dateTime,
                          isActive: true,
                          isCompleted: false,
                          createdAt: reminder?.createdAt ?? DateTime.now(),
                        );
                        await _reminderBox.put(
                          newReminder.id,
                          newReminder.toMap(),
                        );
                        await ReminderService.instance.syncReminder(
                          newReminder,
                        );
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Save'),
                    ),
                  ],
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

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${TimeOfDay.fromDateTime(dateTime).format(context)}';
  }

  Widget _buildReminderTile(Reminder reminder) {
    return MoveOrDeleteDismissible(
      itemKey: ValueKey(reminder.id),
      onConfirmDelete: () => confirmDelete(
        context,
        itemTypeLabel: 'reminder',
        itemName: reminder.title,
      ),
      onDelete: () => _deleteReminder(reminder),
      onMove: () => showMoveToSheet(
        context: context,
        sourceKind: ItemKind.reminder,
        sourceItem: reminder,
      ),
      child: ListTile(
        leading: Checkbox(
          value: reminder.isCompleted,
          onChanged: (_) => _toggleCompleted(reminder),
        ),
        title: Text(
          reminder.title,
          style: reminder.isCompleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          reminder.note.isEmpty
              ? _formatDateTime(reminder.dateTime)
              : '${_formatDateTime(reminder.dateTime)} · ${reminder.note}',
        ),
        trailing: const Icon(Icons.notifications, color: Colors.purple),
        onTap: () => _openReminderSheet(reminder),
        onLongPress: () => showMoveToSheet(
          context: context,
          sourceKind: ItemKind.reminder,
          sourceItem: reminder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _reminderBox.listenable(),
      builder: (context, Box<dynamic> box, _) {
        final reminders = _loadReminders();
        final upcoming = reminders.where((r) => !r.isCompleted).toList()
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
        final completed = reminders.where((r) => r.isCompleted).toList()
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

        return Scaffold(
          appBar: TypeAppBar(title: 'Reminders', hint: ItemKind.reminder.hint),
          body: Column(
            children: [
              if (_showMoveHint && reminders.isNotEmpty)
                MoveHintBanner(onDismiss: _dismissMoveHint),
              Expanded(
                child: reminders.isEmpty
                    ? const Center(
                        child: Text('No reminders yet. Tap + to add one.'),
                      )
                    : ListView(
                        children: [
                          if (upcoming.isNotEmpty) ...[
                            ListSectionHeader(
                              label: 'Upcoming',
                              count: upcoming.length,
                            ),
                            for (final reminder in upcoming)
                              _buildReminderTile(reminder),
                          ],
                          if (completed.isNotEmpty) ...[
                            ListSectionHeader(
                              label: 'Completed',
                              count: completed.length,
                            ),
                            for (final reminder in completed)
                              _buildReminderTile(reminder),
                          ],
                        ],
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openReminderSheet(),
            backgroundColor: Colors.purple,
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}
