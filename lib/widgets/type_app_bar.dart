import 'package:flutter/material.dart';

/// A consistent AppBar used across the Today/Tasks/Reminders/Notes tabs:
/// the section title plus a one-line hint underneath explaining what that
/// item type is for, so it's always obvious what kind of thing you're
/// looking at and how it differs from the others.
class TypeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String hint;
  final List<Widget>? actions;

  const TypeAppBar({
    super.key,
    required this.title,
    required this.hint,
    this.actions,
  });

  static const double _height = 64;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: _height,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(_height);
}
