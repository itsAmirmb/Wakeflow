/// A free-text note attached to a category: rules, reminders, resources.
/// A category can have any number of them (or none).
class CategoryNote {
  final String id;
  final String categoryId;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CategoryNote({
    required this.id,
    required this.categoryId,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
  });

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

  CategoryNote edited(String newText, {DateTime? now}) => CategoryNote(
    id: id,
    categoryId: categoryId,
    text: newText.trim(),
    createdAt: createdAt,
    updatedAt: now ?? DateTime.now(),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'categoryId': categoryId,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CategoryNote.fromMap(Map<String, Object?> map) => CategoryNote(
    id: map['id'] as String,
    categoryId: map['categoryId'] as String,
    text: map['text'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
    updatedAt: DateTime.parse(map['updatedAt'] as String),
  );
}
