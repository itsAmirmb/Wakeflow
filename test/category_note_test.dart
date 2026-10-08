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
    expect(note.isDone, isFalse);

    final copy = CategoryNote.fromMap(note.toMap());
    expect(copy.id, note.id);
    expect(copy.categoryId, 'trading');
    expect(copy.text, note.text);
    expect(copy.createdAt, now);
    expect(copy.updatedAt, now);
    expect(copy.doneAt, isNull);
  });

  test('editing keeps id, creation time and done state', () {
    final created = DateTime(2026, 10, 7, 9);
    final done = CategoryNote.create(
      categoryId: 'academic',
      text: 'Read chapter 3',
      now: created,
    ).withDone(true, now: DateTime(2026, 10, 7, 10));
    final later = DateTime(2026, 10, 8, 9);
    final edited = done.edited(' Read chapter 4 ', now: later);
    expect(edited.id, done.id);
    expect(edited.createdAt, created);
    expect(edited.updatedAt, later);
    expect(edited.text, 'Read chapter 4');
    expect(edited.isDone, isTrue);
  });

  test('ticking off and un-ticking toggles only the done state', () {
    final note = CategoryNote.create(
      categoryId: 'gym',
      text: 'Warm up',
      now: DateTime(2026, 10, 7, 9),
    );
    final tickedAt = DateTime(2026, 10, 7, 11);
    final ticked = note.withDone(true, now: tickedAt);
    expect(ticked.isDone, isTrue);
    expect(ticked.doneAt, tickedAt);
    expect(ticked.text, note.text);
    expect(ticked.updatedAt, note.updatedAt);

    // The done state survives storage.
    expect(CategoryNote.fromMap(ticked.toMap()).doneAt, tickedAt);

    final reopened = ticked.withDone(false);
    expect(reopened.isDone, isFalse);
    expect(reopened.doneAt, isNull);
  });

  test('stats report the notes still open', () {
    const stats = NoteStats(5, 2);
    expect(stats.open, 3);
    expect(const NoteStats(2, 2).open, 0);
  });
}
