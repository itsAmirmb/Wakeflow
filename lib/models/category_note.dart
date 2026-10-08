/// A free-text note attached to a category: rules, reminders, resources.
/// A category can have any number of them (or none). Each can be ticked off
/// (and un-ticked) while working in a block.
class CategoryNote {
  final String id;
  final String categoryId;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// When the note was ticked off; null while it is still open.
  final DateTime? doneAt;

  /// The app day (yyyy-MM-dd) it was ticked on, so the tick can expire when
  /// the user chooses not to keep ticks for the next day.
  final String? doneDay;

  const CategoryNote({
    required this.id,
    required this.categoryId,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.doneAt,
    this.doneDay,
  });

  bool get isDone => doneAt != null;

  /// Ticked off, and the tick still counts today: always when ticks are kept
  /// across days, otherwise only when it was made today.
  bool isDoneOn(String today, {required bool keepAcrossDays}) =>
      doneAt != null && (keepAcrossDays || doneDay == today);

  /// This note as it should be seen today: a tick that has expired shows as
  /// open. Nothing is deleted, so switching the setting back brings it back.
  CategoryNote effective(String today, {required bool keepAcrossDays}) =>
      doneAt == null || isDoneOn(today, keepAcrossDays: keepAcrossDays)
      ? this
      : CategoryNote(
          id: id,
          categoryId: categoryId,
          text: text,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

  factory CategoryNote.create({
    required String categoryId,
    required String text,
    DateTime? now,
  }) {
    final time = now ?? DateTime.now();
    return CategoryNote(
      id: 'note_${time.microsecondsSinceEpoch}',
      categoryId: categoryId,
      text: text.trim(),
      createdAt: time,
      updatedAt: time,
    );
  }

  /// Editing the text keeps the done state: fixing a typo is not "undo".
  CategoryNote edited(String newText, {DateTime? now}) => CategoryNote(
    id: id,
    categoryId: categoryId,
    text: newText.trim(),
    createdAt: createdAt,
    updatedAt: now ?? DateTime.now(),
    doneAt: doneAt,
    doneDay: doneDay,
  );

  /// Ticked off (or back to open) without touching anything else.
  CategoryNote withDone(bool done, {DateTime? now, String? day}) =>
      CategoryNote(
        id: id,
        categoryId: categoryId,
        text: text,
        createdAt: createdAt,
        updatedAt: updatedAt,
        doneAt: done ? (now ?? DateTime.now()) : null,
        doneDay: done ? day : null,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'categoryId': categoryId,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'doneAt': doneAt?.toIso8601String(),
    'doneDay': doneDay,
  };

  factory CategoryNote.fromMap(Map<String, Object?> map) => CategoryNote(
    id: map['id'] as String,
    categoryId: map['categoryId'] as String,
    text: map['text'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
    updatedAt: DateTime.parse(map['updatedAt'] as String),
    doneAt: map['doneAt'] == null
        ? null
        : DateTime.parse(map['doneAt'] as String),
    doneDay: map['doneDay'] as String?,
  );
}

/// How many notes a category has and how many are ticked off.
class NoteStats {
  final int total;
  final int done;

  const NoteStats(this.total, this.done);

  int get open => total - done;
}
