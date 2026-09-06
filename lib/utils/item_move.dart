import 'package:flutter/material.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

const String _moveHintSeenKey = 'hasSeenMoveHint_v1';

/// Whether the user has already dismissed the "how to move an item" tip.
/// Shared across the Tasks/Reminders/Notes screens — it's the same gesture
/// everywhere, so seeing it once anywhere is enough.
bool hasSeenMoveHint(Box<dynamic> settingsBox) {
  return settingsBox.get(_moveHintSeenKey, defaultValue: false) as bool;
}

Future<void> markMoveHintSeen(Box<dynamic> settingsBox) async {
  await settingsBox.put(_moveHintSeenKey, true);
}

/// The four kinds of item this app tracks. Centralizing their display
/// name/hint/icon/color here means every screen describes and colors each
/// type identically instead of drifting apart.
enum ItemKind { habit, task, reminder, note }

extension ItemKindInfo on ItemKind {
  String get label {
    switch (this) {
      case ItemKind.habit:
        return 'Habit';
      case ItemKind.task:
        return 'Task';
      case ItemKind.reminder:
        return 'Reminder';
      case ItemKind.note:
        return 'Note';
    }
  }

  String get pluralLabel => '${label}s';

  /// One-line explanation of what this type is for, shown as a subtitle
  /// under the tab's title and reused in the "Move to..." picker.
  String get hint {
    switch (this) {
      case ItemKind.habit:
        return 'Recurring routines you repeat on a schedule';
      case ItemKind.task:
        return 'One-time to-dos — do it once, check it off, done';
      case ItemKind.reminder:
        return 'A one-off nudge at a specific date and time';
      case ItemKind.note:
        return 'Free-form writing — no due date, no tracking';
    }
  }

  IconData get icon {
    switch (this) {
      case ItemKind.habit:
        return Icons.check_circle;
      case ItemKind.task:
        return Icons.task_alt;
      case ItemKind.reminder:
        return Icons.notifications;
      case ItemKind.note:
        return Icons.sticky_note_2;
    }
  }

  Color get color {
    switch (this) {
      case ItemKind.habit:
        return Colors.blue;
      case ItemKind.task:
        return Colors.green;
      case ItemKind.reminder:
        return Colors.purple;
      case ItemKind.note:
        return Colors.amber.shade800;
    }
  }
}

/// Fields common enough across Habit/Task/Reminder/Note to carry an item's
/// content across a move, even though each type stores them differently.
class _CommonFields {
  final String name;
  final String description;
  final DateTime? dueDate;
  final int? hour;
  final int? minute;
  final PriorityLevel priorityLevel;
  final List<String> environmentIds;

  _CommonFields({
    required this.name,
    required this.description,
    this.dueDate,
    this.hour,
    this.minute,
    this.priorityLevel = PriorityLevel.core,
    this.environmentIds = const [],
  });
}

_CommonFields _extractCommon(ItemKind kind, dynamic item) {
  switch (kind) {
    case ItemKind.habit:
      final habit = item as Habit;
      return _CommonFields(
        name: habit.name,
        description: habit.description,
        priorityLevel: habit.priorityLevel,
        environmentIds: habit.environmentIds,
        hour: habit.reminderEnabled ? habit.reminderHour : null,
        minute: habit.reminderEnabled ? habit.reminderMinute : null,
      );
    case ItemKind.task:
      final task = item as OneTimeTask;
      return _CommonFields(
        name: task.name,
        description: task.description,
        dueDate: task.dueDate,
        priorityLevel: task.priorityLevel,
        environmentIds: task.environmentIds,
        hour: task.reminderEnabled ? task.reminderHour : null,
        minute: task.reminderEnabled ? task.reminderMinute : null,
      );
    case ItemKind.reminder:
      final reminder = item as Reminder;
      return _CommonFields(
        name: reminder.title,
        description: reminder.note,
        dueDate: DateTime(
          reminder.dateTime.year,
          reminder.dateTime.month,
          reminder.dateTime.day,
        ),
        hour: reminder.dateTime.hour,
        minute: reminder.dateTime.minute,
      );
    case ItemKind.note:
      final note = item as Note;
      return _CommonFields(
        name: note.title.isEmpty ? 'Untitled' : note.title,
        description: note.body,
      );
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _formatTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

Future<DateTime?> _pickDateTime(BuildContext context, {DateTime? initial}) async {
  final fallback = DateTime.now().add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: initial ?? fallback,
    firstDate: DateTime.now().subtract(const Duration(days: 1)),
    lastDate: DateTime.now().add(const Duration(days: 3650)),
  );
  if (date == null || !context.mounted) {
    return null;
  }
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial ?? fallback),
  );
  if (time == null) {
    return null;
  }
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<bool?> _confirmMove(
  BuildContext context,
  ItemKind from,
  ItemKind to,
  String name,
) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Move to ${to.pluralLabel}?'),
      content: Text(
        '"$name" will be created as a ${to.label.toLowerCase()}'
        '${from == ItemKind.habit ? ' and the original habit will be archived.' : ' and removed from ${from.pluralLabel.toLowerCase()}.'}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Move'),
        ),
      ],
    ),
  );
}

/// Shows the "Move to..." picker for [sourceItem] (of type [sourceKind]),
/// then performs the move if the user picks a destination and confirms it.
Future<void> showMoveToSheet({
  required BuildContext context,
  required ItemKind sourceKind,
  required dynamic sourceItem,
}) async {
  final targets = ItemKind.values.where((kind) => kind != sourceKind).toList();
  final target = await showModalBottomSheet<ItemKind>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Move to...',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            for (final kind in targets)
              ListTile(
                leading: Icon(kind.icon, color: kind.color),
                title: Text(kind.pluralLabel),
                subtitle: Text(kind.hint),
                onTap: () => Navigator.of(sheetContext).pop(kind),
              ),
          ],
        ),
      );
    },
  );
  if (target == null || !context.mounted) {
    return;
  }
  await moveItem(
    context: context,
    sourceKind: sourceKind,
    sourceItem: sourceItem,
    targetKind: target,
  );
}

/// Converts [sourceItem] into a new item of [targetKind] and removes it
/// from its original type (habits are archived, everything else deleted,
/// mirroring how each type is already retired elsewhere in the app).
Future<void> moveItem({
  required BuildContext context,
  required ItemKind sourceKind,
  required dynamic sourceItem,
  required ItemKind targetKind,
}) async {
  final common = _extractCommon(sourceKind, sourceItem);

  DateTime? reminderDateTime;
  if (targetKind == ItemKind.reminder) {
    if (common.dueDate != null) {
      reminderDateTime = DateTime(
        common.dueDate!.year,
        common.dueDate!.month,
        common.dueDate!.day,
        common.hour ?? 9,
        common.minute ?? 0,
      );
    }
    if (reminderDateTime == null || !reminderDateTime.isAfter(DateTime.now())) {
      if (!context.mounted) {
        return;
      }
      final picked = await _pickDateTime(context, initial: reminderDateTime);
      if (picked == null) {
        return;
      }
      reminderDateTime = picked;
    }
  }

  if (!context.mounted) {
    return;
  }
  final confirmed = await _confirmMove(context, sourceKind, targetKind, common.name);
  if (confirmed != true) {
    return;
  }

  switch (targetKind) {
    case ItemKind.habit:
      final habitBox = Hive.box(HiveBoxNames.habits);
      final habit = Habit(
        id: const Uuid().v4(),
        name: common.name,
        description: common.description,
        priorityLevel: common.priorityLevel,
        environmentIds: common.environmentIds,
        createdAt: DateTime.now(),
        reminderEnabled: common.hour != null,
        reminderHour: common.hour,
        reminderMinute: common.minute,
      );
      await habitBox.put(habit.id, habit.toMap());
      await ReminderService.instance.syncHabitReminder(habit);
      break;
    case ItemKind.task:
      final taskBox = Hive.box(HiveBoxNames.oneTimeTasks);
      final task = OneTimeTask(
        id: const Uuid().v4(),
        name: common.name,
        description: common.description,
        dueDate: common.dueDate,
        priorityLevel: common.priorityLevel,
        environmentIds: common.environmentIds,
        reminderEnabled: common.hour != null && common.dueDate != null,
        reminderHour: common.hour,
        reminderMinute: common.minute,
        createdAt: DateTime.now(),
      );
      await taskBox.put(task.id, task.toMap());
      await ReminderService.instance.syncTaskReminder(task);
      break;
    case ItemKind.reminder:
      final reminderBox = Hive.box(HiveBoxNames.reminders);
      final reminder = Reminder(
        id: const Uuid().v4(),
        title: common.name,
        note: common.description,
        dateTime: reminderDateTime!,
        createdAt: DateTime.now(),
      );
      await reminderBox.put(reminder.id, reminder.toMap());
      await ReminderService.instance.syncReminder(reminder);
      break;
    case ItemKind.note:
      final noteBox = Hive.box(HiveBoxNames.notes);
      final scheduleLine = common.dueDate == null
          ? ''
          : 'Was due ${_formatDate(common.dueDate!)}'
                '${common.hour != null ? ' at ${_formatTime(common.hour!, common.minute ?? 0)}' : ''}'
                '\n\n';
      final note = Note(
        id: const Uuid().v4(),
        title: common.name,
        body: '$scheduleLine${common.description}',
        createdAt: DateTime.now(),
      );
      await noteBox.put(note.id, note.toMap());
      break;
  }

  switch (sourceKind) {
    case ItemKind.habit:
      final habit = sourceItem as Habit;
      final habitBox = Hive.box(HiveBoxNames.habits);
      habit.isArchived = true;
      habit.archivedAt = DateTime.now();
      await habitBox.put(habit.id, habit.toMap());
      await ReminderService.instance.syncHabitReminder(habit);
      break;
    case ItemKind.task:
      final task = sourceItem as OneTimeTask;
      final taskBox = Hive.box(HiveBoxNames.oneTimeTasks);
      await taskBox.delete(task.id);
      await ReminderService.instance.cancelTaskReminder(task.id);
      break;
    case ItemKind.reminder:
      final reminder = sourceItem as Reminder;
      final reminderBox = Hive.box(HiveBoxNames.reminders);
      await reminderBox.delete(reminder.id);
      await ReminderService.instance.cancelReminder(reminder.id);
      break;
    case ItemKind.note:
      final note = sourceItem as Note;
      final noteBox = Hive.box(HiveBoxNames.notes);
      await noteBox.delete(note.id);
      break;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved "${common.name}" to ${targetKind.pluralLabel}.')),
    );
  }
}
