import 'package:flutter/material.dart';
import 'package:habit_tracker/archived_habits_screen.dart';
import 'package:habit_tracker/history_screen.dart';
import 'package:habit_tracker/manage_environments_screen.dart';
import 'package:habit_tracker/manage_habits_screen.dart';
import 'package:habit_tracker/paused_sessions_screen.dart';
import 'package:habit_tracker/weekly_time_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Manage habits'),
            subtitle: const Text('Reorder, edit, filter, and archive habits'),
            onTap: () => _open(context, const ManageHabitsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Archived habits'),
            onTap: () => _open(context, const ArchivedHabitsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Manage environments'),
            subtitle: const Text('Deep Work, College, Quick Task, and custom ones'),
            onTap: () => _open(context, const ManageEnvironmentsScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('History'),
            onTap: () => _open(context, const HistoryScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Weekly time budget'),
            onTap: () => _open(context, const WeeklyTimeScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.event_busy),
            title: const Text('Paused sessions'),
            onTap: () => _open(context, const PausedSessionsScreen()),
          ),
        ],
      ),
    );
  }
}
