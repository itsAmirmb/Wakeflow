import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/category.dart';
import '../models/category_note.dart';
import '../services/database_service.dart';
import '../services/note_context.dart';
import '../widgets/empty_state.dart';

const int _maxNoteLength = 2000;

/// Done notes are struck through and dimmed, so the state reads at a glance
/// without relying on colour alone.
TextStyle? _noteStyle(BuildContext context, CategoryNote note) {
  final base = Theme.of(context).textTheme.bodyLarge;
  if (!note.isDone) return base;
  return base?.copyWith(
    decoration: TextDecoration.lineThrough,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );
}

/// [notes] with the item at [oldIndex] moved to where ReorderableListView
/// says it was dropped ([newIndex] still counts the item itself when moving
/// down, hence the adjustment).
List<CategoryNote> _moved(
  List<CategoryNote> notes,
  int oldIndex,
  int newIndex,
) {
  if (newIndex > oldIndex) newIndex -= 1;
  final result = [...notes];
  result.insert(newIndex, result.removeAt(oldIndex));
  return result;
}

/// Manage a category's notes: add, edit, tick off, reorder, delete (with undo).
class CategoryNotesScreen extends StatefulWidget {
  final Category category;

  const CategoryNotesScreen({super.key, required this.category});

  @override
  State<CategoryNotesScreen> createState() => _CategoryNotesScreenState();
}

class _CategoryNotesScreenState extends State<CategoryNotesScreen> {
  List<CategoryNote>? _notes;
  bool _failed = false;
  String _today = '';

  DatabaseService get _db => DatabaseService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final noteContext = await loadNoteContext(_db);
      final notes = await _db.getNotes(
        widget.category.id,
        today: noteContext.today,
        keepAcrossDays: noteContext.keepAcrossDays,
      );
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _today = noteContext.today;
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
    try {
      if (existing == null) {
        // New notes always go to the end of the list.
        await _db.addNote(
          CategoryNote.create(categoryId: widget.category.id, text: text),
        );
      } else {
        await _db.saveNote(existing.edited(text));
      }
      await _load();
    } catch (_) {
      _toast('Could not save the note. Please try again.');
    }
  }

  /// Instant on screen, saved in the background; put back if saving fails.
  Future<void> _toggle(CategoryNote note) async {
    final notes = _notes;
    if (notes == null) return;
    final updated = note.withDone(!note.isDone, day: _today);
    final index = notes.indexWhere((n) => n.id == note.id);
    if (index == -1) return;
    setState(() => _notes = [...notes]..[index] = updated);
    try {
      await _db.setNoteDone(note.id, updated.doneAt, updated.doneDay);
    } catch (_) {
      if (mounted) {
        setState(() => _notes = [...?_notes]..[index] = note);
      }
      _toast('Could not update the note.');
    }
  }

  /// Instant on screen, saved in the background; reloaded if saving fails.
  Future<void> _reorder(int oldIndex, int newIndex) async {
    final notes = _notes;
    if (notes == null) return;
    final reordered = _moved(notes, oldIndex, newIndex);
    setState(() => _notes = reordered);
    try {
      await _db.reorderNotes([for (final n in reordered) n.id]);
    } catch (_) {
      _toast('Could not save the new order.');
      await _load();
    }
  }

  Future<void> _uncheckAll() async {
    try {
      await _db.uncheckAllNotes(widget.category.id);
      await _load();
    } catch (_) {
      _toast('Could not update the notes.');
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
    final anyDone = notes?.any((n) => n.isDone) ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text('${category.icon} ${category.name} notes'),
        actions: [
          if (anyDone)
            IconButton(
              tooltip: 'Untick all',
              icon: const Icon(Icons.remove_done),
              onPressed: _uncheckAll,
            ),
        ],
      ),
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
          : ReorderableListView.builder(
              // Room for the floating button under the last note.
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              buildDefaultDragHandles: false,
              itemCount: notes.length,
              onReorder: _reorder,
              itemBuilder: (context, index) {
                final note = notes[index];
                return Card(
                  key: ValueKey(note.id),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Checkbox(
                        value: note.isDone,
                        onChanged: (_) => _toggle(note),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => _addOrEdit(note),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              note.text,
                              style: _noteStyle(context, note),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete note',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(note),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(4, 12, 12, 12),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
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

/// Bottom sheet with a category's notes, for use mid-work: tap a note to
/// tick it off, tap again to undo; long-press copies its text; drag the
/// handle to reorder; the + button adds a note at the end. The Edit button
/// opens the full manager.
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
  List<CategoryNote>? _notes;
  bool _failed = false;
  String _today = '';

  DatabaseService get _db => DatabaseService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final noteContext = await loadNoteContext(_db);
      final notes = await _db.getNotes(
        widget.category.id,
        today: noteContext.today,
        keepAcrossDays: noteContext.keepAcrossDays,
      );
      if (mounted) {
        setState(() {
          _notes = notes;
          _today = noteContext.today;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Instant on screen, saved in the background; put back if saving fails.
  Future<void> _toggle(int index) async {
    final notes = _notes;
    if (notes == null) return;
    final note = notes[index];
    final updated = note.withDone(!note.isDone, day: _today);
    setState(() => _notes = [...notes]..[index] = updated);
    try {
      await _db.setNoteDone(note.id, updated.doneAt, updated.doneDay);
    } catch (_) {
      if (!mounted) return;
      setState(() => _notes = [...?_notes]..[index] = note);
      _toast('Could not update the note.');
    }
  }

  Future<void> _copy(CategoryNote note) async {
    await Clipboard.setData(ClipboardData(text: note.text));
    if (mounted) _toast('Note copied');
  }

  Future<void> _add() async {
    final text = await _askText(context);
    if (text == null || !mounted) return;
    try {
      // New notes always go to the end of the list.
      await _db.addNote(
        CategoryNote.create(categoryId: widget.category.id, text: text),
      );
      await _load();
    } catch (_) {
      if (mounted) _toast('Could not save the note. Please try again.');
    }
  }

  /// Instant on screen, saved in the background; reloaded if saving fails.
  Future<void> _reorder(int oldIndex, int newIndex) async {
    final notes = _notes;
    if (notes == null) return;
    final reordered = _moved(notes, oldIndex, newIndex);
    setState(() => _notes = reordered);
    try {
      await _db.reorderNotes([for (final n in reordered) n.id]);
    } catch (_) {
      if (mounted) _toast('Could not save the new order.');
      await _load();
    }
  }

  Future<void> _edit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryNotesScreen(category: widget.category),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final scheme = Theme.of(context).colorScheme;
    final notes = _notes;
    final done = notes?.where((n) => n.isDone).length ?? 0;
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${category.icon} ${category.name} notes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (notes != null && notes.isNotEmpty)
                        Text(
                          '$done of ${notes.length} done',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Add note',
                  icon: const Icon(Icons.add),
                  onPressed: _add,
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
            child: _failed
                ? const Center(child: Text('Could not load notes.'))
                : notes == null
                ? const Center(child: CircularProgressIndicator())
                : notes.isEmpty
                ? const EmptyState(
                    icon: Icons.sticky_note_2_outlined,
                    message: 'No notes yet. Tap + to add one.',
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    buildDefaultDragHandles: false,
                    itemCount: notes.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      return Column(
                        key: ValueKey(note.id),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            checked: note.isDone,
                            child: ListTile(
                              leading: Icon(
                                note.isDone
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: note.isDone ? scheme.primary : null,
                              ),
                              title: Text(
                                note.text,
                                style: _noteStyle(context, note),
                              ),
                              trailing: ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                              onTap: () => _toggle(index),
                              onLongPress: () => _copy(note),
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
