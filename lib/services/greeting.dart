/// Time-of-day greeting for the Home and Wake screens.
///
/// 05:00-11:59 morning, 12:00-16:59 afternoon, 17:00-21:59 evening. Late
/// night gets a neutral "Hello" instead of a misleading "Good evening".
({String text, String emoji}) greetingFor(DateTime time) {
  final hour = time.hour;
  if (hour >= 5 && hour < 12) return (text: 'Good morning', emoji: '👋');
  if (hour >= 12 && hour < 17) return (text: 'Good afternoon', emoji: '☀️');
  if (hour >= 17 && hour < 22) return (text: 'Good evening', emoji: '🌆');
  return (text: 'Hello', emoji: '🌙');
}
