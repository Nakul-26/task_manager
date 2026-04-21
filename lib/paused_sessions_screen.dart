import 'package:flutter/material.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/reminder_service.dart';
import 'package:habit_tracker/utils/habit_schedule_utils.dart'
    as schedule_utils;
import 'package:habit_tracker/utils/pause_utils.dart';
import 'package:hive_flutter/hive_flutter.dart';

class PausedSessionsScreen extends StatefulWidget {
  final Future<void> Function()? onPausePeriodsChanged;

  const PausedSessionsScreen({super.key, this.onPausePeriodsChanged});

  @override
  State<PausedSessionsScreen> createState() => _PausedSessionsScreenState();
}

class _PausedSessionsScreenState extends State<PausedSessionsScreen> {
  late Box<dynamic> _habitBox;
  late Box<dynamic> _settingsBox;
  List<PausePeriod> _pausePeriods = [];

  @override
  void initState() {
    super.initState();
    _habitBox = Hive.box<dynamic>(HiveBoxNames.habits);
    _settingsBox = Hive.box<dynamic>(HiveBoxNames.appSettings);
    _settingsBox.listenable().addListener(_loadPausePeriods);
    _loadPausePeriods();
  }

  @override
  void dispose() {
    _settingsBox.listenable().removeListener(_loadPausePeriods);
    super.dispose();
  }

  void _loadPausePeriods() {
    if (!mounted) {
      return;
    }
    setState(() {
      _pausePeriods = loadPausePeriods(_settingsBox);
    });
  }

  DateTime _normalizeDate(DateTime date) {
    return schedule_utils.normalizeDate(date);
  }

  String _formatHumanDate(BuildContext context, DateTime date) {
    return MaterialLocalizations.of(
      context,
    ).formatMediumDate(_normalizeDate(date));
  }

  String _statusLabel(PausePeriod period) {
    final today = _normalizeDate(DateTime.now());
    if (!period.startDate.isAfter(today) && !period.endDate.isBefore(today)) {
      return 'Active';
    }
    if (period.startDate.isAfter(today)) {
      return 'Upcoming';
    }
    return 'Past';
  }

  MaterialColor _statusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.orange;
      case 'Upcoming':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  int _durationInDays(PausePeriod period) {
    return period.endDate.difference(period.startDate).inDays + 1;
  }

  Future<void> _savePeriods(List<PausePeriod> pausePeriods) async {
    pausePeriods.sort((a, b) => a.startDate.compareTo(b.startDate));
    await savePausePeriods(_settingsBox, pausePeriods);
    final onPausePeriodsChanged = widget.onPausePeriodsChanged;
    if (onPausePeriodsChanged != null) {
      await onPausePeriodsChanged();
      return;
    }
    await ReminderService.instance.syncAllHabitReminders(_habitBox);
  }

  Future<void> _openPauseDialog({PausePeriod? period, int? index}) async {
    final today = _normalizeDate(DateTime.now());
    DateTime startDate = period?.startDate ?? today;
    DateTime endDate = period?.endDate ?? today;
    final descriptionController = TextEditingController(
      text: period?.description ?? '',
    );

    final savedPeriod = await showDialog<PausePeriod>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickStartDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: startDate,
                firstDate: DateTime(today.year - 5),
                lastDate: DateTime(today.year + 5),
              );
              if (picked == null) {
                return;
              }
              setDialogState(() {
                startDate = _normalizeDate(picked);
                if (endDate.isBefore(startDate)) {
                  endDate = startDate;
                }
              });
            }

            Future<void> pickEndDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: endDate.isBefore(startDate) ? startDate : endDate,
                firstDate: startDate,
                lastDate: DateTime(today.year + 5),
              );
              if (picked == null) {
                return;
              }
              setDialogState(() {
                endDate = _normalizeDate(picked);
              });
            }

            return AlertDialog(
              title: Text(period == null ? 'Add Pause' : 'Edit Pause'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Start date'),
                      subtitle: Text(_formatHumanDate(context, startDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: pickStartDate,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('End date'),
                      subtitle: Text(_formatHumanDate(context, endDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: pickEndDate,
                    ),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Reason',
                        hintText: 'Tests, travel, vacation, recovery...',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      PausePeriod(
                        startDate: startDate,
                        endDate: endDate,
                        description: descriptionController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    descriptionController.dispose();

    if (savedPeriod == null) {
      return;
    }

    final updatedPeriods = List<PausePeriod>.from(_pausePeriods);
    if (index == null) {
      updatedPeriods.add(savedPeriod);
    } else {
      updatedPeriods[index] = savedPeriod;
    }
    await _savePeriods(updatedPeriods);
  }

  Future<void> _deletePause(int index) async {
    final period = _pausePeriods[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Pause'),
        content: Text(
          'Delete the pause from ${_formatHumanDate(context, period.startDate)} '
          'to ${_formatHumanDate(context, period.endDate)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final updatedPeriods = List<PausePeriod>.from(_pausePeriods)
      ..removeAt(index);
    await _savePeriods(updatedPeriods);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            const Text(
              'No paused sessions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a pause when you want habit tracking to skip a date range.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseCard(PausePeriod period, int index) {
    final status = _statusLabel(period);
    final statusColor = _statusColor(status);
    final duration = _durationInDays(period);
    final description = period.description.trim();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(32),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withAlpha(120)),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit pause',
                  onPressed: () =>
                      _openPauseDialog(period: period, index: index),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete pause',
                  onPressed: () => _deletePause(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatHumanDate(context, period.startDate)} - '
              '${_formatHumanDate(context, period.endDate)}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('$duration ${duration == 1 ? 'day' : 'days'}'),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(description),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paused Sessions')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openPauseDialog(),
        tooltip: 'Add pause',
        child: const Icon(Icons.add),
      ),
      body: _pausePeriods.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88, top: 8),
              itemCount: _pausePeriods.length,
              itemBuilder: (context, index) {
                return _buildPauseCard(_pausePeriods[index], index);
              },
            ),
    );
  }
}
