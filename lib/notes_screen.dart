import 'package:flutter/material.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/note_editor_screen.dart';
import 'package:habit_tracker/utils/delete_feedback.dart';
import 'package:habit_tracker/utils/item_move.dart';
import 'package:habit_tracker/widgets/list_section_header.dart';
import 'package:habit_tracker/widgets/move_hint_banner.dart';
import 'package:habit_tracker/widgets/move_or_delete_dismissible.dart';
import 'package:habit_tracker/widgets/type_app_bar.dart';
import 'package:hive_flutter/hive_flutter.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  late Box<dynamic> _noteBox;
  late Box<dynamic> _settingsBox;
  late bool _showMoveHint;

  @override
  void initState() {
    super.initState();
    _noteBox = Hive.box(HiveBoxNames.notes);
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

  List<Note> _loadNotes() {
    final notes = _noteBox.values
        .map((e) => Note.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    notes.sort((a, b) {
      if (a.pinned != b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return notes;
  }

  Future<void> _openNote([Note? note]) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => NoteEditorScreen(note: note)));
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _deleteNote(Note note) async {
    final removedMap = Map<String, dynamic>.from(note.toMap());
    await _noteBox.delete(note.id);
    if (!mounted) {
      return;
    }
    setState(() {});
    showUndoSnackBar(
      context,
      message: 'Deleted "${note.title.isEmpty ? 'Untitled' : note.title}"',
      onUndo: () => _noteBox.put(note.id, removedMap),
    );
  }

  String _preview(Note note) {
    if (note.body.isEmpty) {
      return 'No content';
    }
    final singleLine = note.body.replaceAll('\n', ' ');
    return singleLine.length > 80
        ? '${singleLine.substring(0, 80)}…'
        : singleLine;
  }

  Widget _buildNoteTile(Note note) {
    return MoveOrDeleteDismissible(
      itemKey: ValueKey(note.id),
      onConfirmDelete: () => confirmDelete(
        context,
        itemTypeLabel: 'note',
        itemName: note.title.isEmpty ? 'Untitled' : note.title,
      ),
      onDelete: () => _deleteNote(note),
      onMove: () => showMoveToSheet(
        context: context,
        sourceKind: ItemKind.note,
        sourceItem: note,
      ),
      child: ListTile(
        leading: Icon(
          note.pinned ? Icons.push_pin : Icons.sticky_note_2_outlined,
          color: Colors.amber[800],
        ),
        title: Text(
          note.title.isEmpty ? 'Untitled' : note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _preview(note),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _openNote(note),
        onLongPress: () => showMoveToSheet(
          context: context,
          sourceKind: ItemKind.note,
          sourceItem: note,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _noteBox.listenable(),
      builder: (context, Box<dynamic> box, _) {
        final notes = _loadNotes();
        final pinned = notes.where((n) => n.pinned).toList();
        final others = notes.where((n) => !n.pinned).toList();
        return Scaffold(
          appBar: TypeAppBar(title: 'Notes', hint: ItemKind.note.hint),
          body: Column(
            children: [
              if (_showMoveHint && notes.isNotEmpty)
                MoveHintBanner(onDismiss: _dismissMoveHint),
              Expanded(
                child: notes.isEmpty
                    ? const Center(
                        child: Text('No notes yet. Tap + to add one.'),
                      )
                    : ListView(
                        children: [
                          if (pinned.isNotEmpty) ...[
                            ListSectionHeader(
                              label: 'Pinned',
                              count: pinned.length,
                            ),
                            for (final note in pinned) _buildNoteTile(note),
                          ],
                          if (others.isNotEmpty) ...[
                            if (pinned.isNotEmpty)
                              ListSectionHeader(
                                label: 'Others',
                                count: others.length,
                              ),
                            for (final note in others) _buildNoteTile(note),
                          ],
                        ],
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openNote(),
            backgroundColor: Colors.amber[800],
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}
