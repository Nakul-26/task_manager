import 'package:flutter/material.dart';

/// Shared section-header style used by the Tasks, Reminders, and Notes
/// list screens so grouped lists ("Overdue", "Upcoming", "Pinned", ...)
/// look and feel the same across all three.
class ListSectionHeader extends StatelessWidget {
  final String label;
  final int count;

  const ListSectionHeader({super.key, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        '$label ($count)',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}
