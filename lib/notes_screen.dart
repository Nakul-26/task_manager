import 'package:flutter/material.dart';
import 'package:habit_tracker/box_names.dart';
import 'package:habit_tracker/models.dart';
import 'package:habit_tracker/note_editor_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  late Box<dynamic> _noteBox;

  @override
  void initState() {
    super.initState();
    _noteBox = Hive.box(HiveBoxNames.notes);
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
    await _noteBox.delete(note.id);
    setState(() {});
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _noteBox.listenable(),
      builder: (context, Box<dynamic> box, _) {
        final notes = _loadNotes();
        return Scaffold(
          appBar: AppBar(title: const Text('Notes')),
          body: notes.isEmpty
              ? const Center(child: Text('No notes yet. Tap + to add one.'))
              : ListView.builder(
                  itemCount: notes.length,
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    return Dismissible(
                      key: ValueKey(note.id),
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      secondaryBackground: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deleteNote(note),
                      child: ListTile(
                        leading: Icon(
                          note.pinned
                              ? Icons.push_pin
                              : Icons.sticky_note_2_outlined,
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
                      ),
                    );
                  },
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
