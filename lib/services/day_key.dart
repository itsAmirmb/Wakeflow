/// Formats [date] as a yyyy-MM-dd key used to tag blocks by day in
/// the database (and to detect "is this still today").
String dayKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
