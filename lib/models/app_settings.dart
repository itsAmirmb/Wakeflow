/// App-wide settings, editable from the Settings tab. Stored as a
/// single row (id-less key-value would also work, but a single row
/// is simpler for the handful of fields we have).
class AppSettings {
  final int bufferMinutes;
  final int wakeReminderHour;
  final int wakeReminderMinute;

  const AppSettings({
    this.bufferMinutes = 10,
    this.wakeReminderHour = 8,
    this.wakeReminderMinute = 0,
  });

  AppSettings copyWith({
    int? bufferMinutes,
    int? wakeReminderHour,
    int? wakeReminderMinute,
  }) {
    return AppSettings(
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      wakeReminderHour: wakeReminderHour ?? this.wakeReminderHour,
      wakeReminderMinute: wakeReminderMinute ?? this.wakeReminderMinute,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': 0, // single row
      'bufferMinutes': bufferMinutes,
      'wakeReminderHour': wakeReminderHour,
      'wakeReminderMinute': wakeReminderMinute,
    };
  }

  factory AppSettings.fromMap(Map<String, Object?> map) {
    return AppSettings(
      bufferMinutes: map['bufferMinutes'] as int,
      wakeReminderHour: map['wakeReminderHour'] as int,
      wakeReminderMinute: map['wakeReminderMinute'] as int,
    );
  }
}
