import 'package:flutter/material.dart';

/// One-time, dismissible tip shown at the top of Tasks/Reminders/Notes so
/// the swipe-right-to-move / long-press gesture is actually discoverable
/// instead of being a hidden feature only a developer would know about.
class MoveHintBanner extends StatelessWidget {
  final VoidCallback onDismiss;

  const MoveHintBanner({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_horiz, color: colorScheme.onPrimaryContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tip: swipe an item right, or long-press it, to move it to a '
              'Habit, Task, Reminder, or Note.',
              style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 13),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: colorScheme.onPrimaryContainer, size: 18),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
