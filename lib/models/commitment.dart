import '../services/day_key.dart';

/// A fixed time span the planner must not schedule blocks into.
typedef BusyInterval = ({DateTime start, DateTime end});

/// A fixed event such as a class or a work shift. Either weekly on chosen
/// weekdays, or a single date. Times are minutes after midnight, same day
/// (an event crossing midnight is entered as two events).
class Commitment {
  final String id;
  final String title;
  final int startMinutes;
  final int endMinutes;

  /// DateTime.weekday values (1 = Monday ... 7 = Sunday). Weekly events only.
  final Set<int> weekdays;

  /// yyyy-MM-dd for a one-off event; null for a weekly one.
  final String? date;

  /// Lets a weekly event be paused (holidays) without deleting it.
  final bool enabled;

  const Commitment({
    required this.id,
    required this.title,
    required this.startMinutes,
    required this.endMinutes,
    this.weekdays = const {},
    this.date,
    this.enabled = true,
  });

  bool get isRecurring => date == null;

  bool occursOn(DateTime day) =>
      enabled &&
      (isRecurring ? weekdays.contains(day.weekday) : date == dayKey(day));

  BusyInterval intervalOn(DateTime day) => (
    start: DateTime(
      day.year,
      day.month,
      day.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    ),
    end: DateTime(
      day.year,
      day.month,
      day.day,
      endMinutes ~/ 60,
      endMinutes % 60,
    ),
  );

  Commitment copyWith({
    String? title,
    int? startMinutes,
    int? endMinutes,
    Set<int>? weekdays,
    String? date,
    bool? enabled,
  }) => Commitment(
    id: id,
    title: title ?? this.title,
    startMinutes: startMinutes ?? this.startMinutes,
    endMinutes: endMinutes ?? this.endMinutes,
    weekdays: weekdays ?? this.weekdays,
    date: date ?? this.date,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
    'weekdays': (weekdays.toList()..sort()).join(','),
    'onDate': date,
    'enabled': enabled ? 1 : 0,
  };

  factory Commitment.fromMap(Map<String, Object?> map) => Commitment(
    id: map['id'] as String,
    title: map['title'] as String,
    startMinutes: map['startMinutes'] as int,
    endMinutes: map['endMinutes'] as int,
    weekdays: {
      for (final part in ((map['weekdays'] as String?) ?? '').split(','))
        if (int.tryParse(part) case final day? when day >= 1 && day <= 7) day,
    },
    date: map['onDate'] as String?,
    enabled: (map['enabled'] as int? ?? 1) == 1,
  );

  static String hm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  static const weekdayNames = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };
}
