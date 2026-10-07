const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Human label for a yyyy-MM-dd [day]: "Today", "Yesterday", "Mon, Oct 5",
/// or with the year when it is not the year of [today] (also yyyy-MM-dd,
/// the app's current day, which follows the day-reset time).
String formatDayLabel(String day, {required String today}) {
  if (day == today) return 'Today';
  final date = DateTime.parse(day);
  final now = DateTime.parse(today);
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  if (date.year == yesterday.year &&
      date.month == yesterday.month &&
      date.day == yesterday.day) {
    return 'Yesterday';
  }
  final base =
      '${_weekdays[date.weekday - 1]}, ${_months[date.month - 1]} ${date.day}';
  return date.year == now.year ? base : '$base, ${date.year}';
}
