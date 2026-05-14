import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/utils/execution_environment_utils.dart';
import 'package:hive_flutter/hive_flutter.dart';

final Map<IconData, String> _environmentIconLabels = {
  Icons.psychology: 'Focus',
  Icons.school: 'Campus',
  Icons.flash_on: 'Fast',
  Icons.home: 'Home',
  Icons.work: 'Work',
  Icons.book: 'Study',
  Icons.timer: 'Timer',
  Icons.task_alt: 'Tasks',
  Icons.self_improvement: 'Calm',
  Icons.laptop: 'Laptop',
  Icons.coffee: 'Coffee',
  Icons.directions_run: 'Move',
};

class ManageEnvironmentsScreen extends StatefulWidget {
  const ManageEnvironmentsScreen({super.key});

  @override
  State<ManageEnvironmentsScreen> createState() =>
      _ManageEnvironmentsScreenState();
}

class _ManageEnvironmentsScreenState extends State<ManageEnvironmentsScreen> {
  late Box<dynamic> _settingsBox;
  List<ExecutionEnvironment> _environments = [];

  @override
  void initState() {
    super.initState();
    _settingsBox = Hive.box(HiveBoxNames.appSettings);
    _loadEnvironments();
    _settingsBox.listenable().addListener(_loadEnvironments);
  }

  @override
  void dispose() {
    _settingsBox.listenable().removeListener(_loadEnvironments);
    super.dispose();
  }

  void _loadEnvironments() {
    _environments = loadExecutionEnvironments(_settingsBox);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveEnvironments(List<ExecutionEnvironment> environments) async {
    await saveExecutionEnvironments(_settingsBox, environments);
    _loadEnvironments();
  }

  Future<void> _openEditor({ExecutionEnvironment? environment}) async {
    final saved = await showDialog<ExecutionEnvironment>(
      context: context,
      builder: (dialogContext) => _EnvironmentEditorDialog(
        environment: environment,
      ),
    );
    if (saved == null) {
      return;
    }

    final updated = List<ExecutionEnvironment>.from(_environments);
    if (environment == null) {
      updated.add(saved);
    } else {
      final index = updated.indexWhere((item) => item.id == environment.id);
      if (index >= 0) {
        updated[index] = saved;
      }
    }
    await _saveEnvironments(updated);
  }

  void _showEnvironmentActions(
    BuildContext context,
    ExecutionEnvironment environment,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit environment'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openEditor(environment: environment);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete environment'),
                enabled: !environment.isBuiltIn,
                onTap: environment.isBuiltIn
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        _deleteEnvironment(environment);
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteEnvironment(ExecutionEnvironment environment) async {
    if (environment.isBuiltIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Built-in environments cannot be deleted.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete environment'),
        content: Text('Delete "${environment.name}"?'),
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

    final updated =
        _environments.where((item) => item.id != environment.id).toList();
    await _saveEnvironments(updated);
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset defaults'),
        content: const Text(
          'Are you sure you want to restore the built-in environments?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _saveEnvironments(defaultExecutionEnvironments());
  }

  Future<void> _reorderEnvironments(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final updated = List<ExecutionEnvironment>.from(_environments);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    await _saveEnvironments(updated);
  }

  String _subtitle(ExecutionEnvironment environment) {
    if (environment.description.trim().isEmpty) {
      return environment.isBuiltIn ? 'Built-in' : 'Custom environment';
    }
    return environment.description;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Environments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Reset defaults',
            onPressed: _resetDefaults,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add environment',
            onPressed: () => _openEditor(),
          ),
        ],
      ),
      body: _environments.isEmpty
          ? const Center(child: Text('No environments configured.'))
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              buildDefaultDragHandles: false,
              itemCount: _environments.length,
              onReorder: _reorderEnvironments,
              itemBuilder: (context, index) {
                final environment = _environments[index];
                return Card(
                  key: ValueKey(environment.id),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: environment.color.withValues(alpha: 0.18),
                      child: Icon(environment.icon, color: environment.color),
                    ),
                    title: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            environment.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (environment.isBuiltIn)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Chip(
                              label: Text('Built-in'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      _subtitle(environment),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.more_vert),
                          tooltip: 'Environment actions',
                          onPressed: () =>
                              _showEnvironmentActions(context, environment),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _EnvironmentEditorDialog extends StatefulWidget {
  final ExecutionEnvironment? environment;

  const _EnvironmentEditorDialog({this.environment});

  @override
  State<_EnvironmentEditorDialog> createState() =>
      _EnvironmentEditorDialogState();
}

class _EnvironmentEditorDialogState extends State<_EnvironmentEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late IconData _icon;
  late Color _color;

  static const List<IconData> _icons = [
    Icons.psychology,
    Icons.school,
    Icons.flash_on,
    Icons.home,
    Icons.work,
    Icons.book,
    Icons.timer,
    Icons.task_alt,
    Icons.self_improvement,
    Icons.laptop,
    Icons.coffee,
    Icons.directions_run,
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.environment?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.environment?.description ?? '');
    _icon = widget.environment?.icon ?? Icons.psychology;
    _color = widget.environment?.color ?? Colors.blue;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _environmentIdFromName(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (slug.isEmpty) {
      return 'environment-${DateTime.now().millisecondsSinceEpoch}';
    }
    return slug;
  }

  void _pickColor() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pick color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _color,
            onColorChanged: (value) {
              setState(() {
                _color = value;
              });
            },
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final environment = ExecutionEnvironment(
      id: widget.environment?.id ?? _environmentIdFromName(name),
      name: name,
      description: description,
      color: _color,
      iconKey: executionEnvironmentIconKeyFor(_icon),
      isBuiltIn: widget.environment?.isBuiltIn ?? false,
      sortOrder: widget.environment?.sortOrder ?? -1,
    );
    Navigator.of(context).pop(environment);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.environment != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit environment' : 'Add environment'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a name';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
                DropdownButtonFormField<IconData>(
                  initialValue: _icon,
                  decoration: const InputDecoration(labelText: 'Icon'),
                  items: _icons.map((icon) {
                    return DropdownMenuItem(
                      value: icon,
                      child: Text(_environmentIconLabels[icon] ?? 'Icon'),
                    );
                  }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _icon = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Color'),
                trailing: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                ),
                onTap: _pickColor,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
