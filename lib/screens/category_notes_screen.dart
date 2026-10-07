import 'dart:async';

import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/category_note.dart';
import '../services/database_service.dart';
import '../widgets/empty_state.dart';

const int _maxNoteLength = 2000;

/// Manage a category's notes: add, edit, delete (with undo).
class CategoryNotesScreen extends StatefulWidget {
  final Category category;

  const CategoryNotesScreen({super.key, required this.category});

  @override
  State<CategoryNotesScreen> createState() => _CategoryNotesScreenState();
}

class _CategoryNotesScreenState extends State<CategoryNotesScreen> {
  List<CategoryNote>? _notes;
  bool _failed = false;

  DatabaseService get _db => DatabaseService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final notes = await _db.getNotes(widget.category.id);
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _toast(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _addOrEdit(CategoryNote? existing) async {
    final text = await _askText(context, initial: existing?.text);
    if (text == null || !mounted) return;
    final note = existing == null
        ? CategoryNote.create(categoryId: widget.category.id, text: text)
        : existing.edited(text);
    try {
      await _db.saveNote(note);
      await _load();
    } catch (_) {
      _toast('Could not save the note. Please try again.');
    }
  }

  Future<void> _delete(CategoryNote note) async {
    try {
      await _db.deleteNote(note.id);
      await _load();
      _toast(
        'Note deleted',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await _db.saveNote(note);
              await _load();
            } catch (_) {
              _toast('Could not restore the note.');
            }
          },
        ),
      );
    } catch (_) {
      _toast('Could not delete the note. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final notes = _notes;
    return Scaffold(
      appBar: AppBar(title: Text('${category.icon} ${category.name} notes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(null),
        icon: const Icon(Icons.add),
        label: const Text('Add note'),
      ),
      body: _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load notes.'),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : notes == null
          ? const Center(child: CircularProgressIndicator())
          : notes.isEmpty
          ? const EmptyState(
              icon: Icons.sticky_note_2_outlined,
              message:
                  'No notes yet. Add rules, reminders or resources you want '
                  'at hand while working on this category.',
            )
          : ListView.builder(
              // Room for the floating button under the last note.
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _addOrEdit(note),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Text(note.text)),
                          IconButton(
                            tooltip: 'Delete note',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(note),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Multi-line editor; returns the trimmed text, or null when cancelled.
Future<String?> _askText(BuildContext context, {String? initial}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NoteDialog(initial: initial),
  );
}

class _NoteDialog extends StatefulWidget {
  final String? initial;

  const _NoteDialog({this.initial});

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'New note' : 'Edit note'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        maxLength: _maxNoteLength,
        textCapitalization: TextCapitalization.sentences,
        keyboardType: TextInputType.multiline,
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // An empty note is never saved.
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Read-first bottom sheet with a category's notes, for use mid-work. The
/// Edit button opens the full manager.
Future<void> showCategoryNotesSheet(BuildContext context, Category category) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _NotesSheet(category: category),
  );
}

class _NotesSheet extends StatefulWidget {
  final Category category;

  const _NotesSheet({required this.category});

  @override
  State<_NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends State<_NotesSheet> {
  late Future<List<CategoryNote>> _future = DatabaseService.instance.getNotes(
    widget.category.id,
  );

  Future<void> _edit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryNotesScreen(category: widget.category),
      ),
    );
    if (!mounted) return;
    setState(() {
      _future = DatabaseService.instance.getNotes(widget.category.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final height = MediaQuery.sizeOf(context).height * 0.6;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${category.icon} ${category.name} notes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<CategoryNote>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Could not load notes.'));
                }
                final notes = snapshot.data;
                if (notes == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (notes.isEmpty) {
                  return const EmptyState(
                    icon: Icons.sticky_note_2_outlined,
                    message: 'No notes yet.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  itemCount: notes.length,
                  separatorBuilder: (context, index) => const Divider(height: 24),
                  itemBuilder: (context, index) =>
                      SelectableText(notes[index].text),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
