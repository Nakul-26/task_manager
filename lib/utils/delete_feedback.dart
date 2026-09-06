import 'package:flutter/material.dart';

/// Shared "are you sure?" dialog for deleting a Task/Reminder/Note (Habit
/// delete already had its own confirmation dialog). Used so a stray swipe
/// can't destroy something instantly and silently.
Future<bool> confirmDelete(
  BuildContext context, {
  required String itemTypeLabel,
  required String itemName,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete this $itemTypeLabel?'),
      content: Text('"$itemName" will be deleted.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shared "Undo" snackbar shown right after a delete goes through, so a
/// confirmed-but-still-accidental delete is one tap away from reversible.
void showUndoSnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
        duration: const Duration(seconds: 4),
      ),
    );
}
