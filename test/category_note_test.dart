import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/category_note.dart';

void main() {
  test('create trims the text and round-trips through the database map', () {
    final now = DateTime(2026, 10, 7, 9, 30);
    final note = CategoryNote.create(
      categoryId: 'trading',
      text: '  Risk max 1% per trade \n',
      now: now,
    );
    expect(note.text, 'Risk max 1% per trade');

    final copy = CategoryNote.fromMap(note.toMap());
    expect(copy.id, note.id);
    expect(copy.categoryId, 'trading');
    expect(copy.text, note.text);
    expect(copy.createdAt, now);
    expect(copy.updatedAt, now);
  });

  test('editing keeps id and creation time, and moves updatedAt', () {
    final created = DateTime(2026, 10, 7, 9);
    final note = CategoryNote.create(
      categoryId: 'academic',
      text: 'Read chapter 3',
      now: created,
    );
    final later = DateTime(2026, 10, 8, 9);
    final edited = note.edited(' Read chapter 4 ', now: later);
    expect(edited.id, note.id);
    expect(edited.createdAt, created);
    expect(edited.updatedAt, later);
    expect(edited.text, 'Read chapter 4');
  });
}
