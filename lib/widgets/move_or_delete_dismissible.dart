import 'package:flutter/material.dart';

/// Shared swipe behavior for Tasks/Reminders/Notes list tiles.
///
/// Previously each list showed the same red "delete" background no matter
/// which way you swiped a tile — two gestures for one action. This widget
/// repurposes the two directions instead: swipe left-to-right to move the
/// item to another type (Habit/Task/Reminder/Note), swipe right-to-left to
/// delete it — but only after [onConfirmDelete] is answered, so a stray
/// swipe can no longer delete something outright.
class MoveOrDeleteDismissible extends StatelessWidget {
  final Key itemKey;
  final Widget child;
  final Future<bool> Function() onConfirmDelete;
  final VoidCallback onDelete;
  final VoidCallback onMove;

  const MoveOrDeleteDismissible({
    required this.itemKey,
    required this.child,
    required this.onConfirmDelete,
    required this.onDelete,
    required this.onMove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: itemKey,
      background: Container(
        color: Colors.blue,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, color: Colors.white),
            SizedBox(width: 8),
            Text('Move', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onMove();
          return false;
        }
        return onConfirmDelete();
      },
      onDismissed: (_) => onDelete(),
      child: child,
    );
  }
}
