/// App-wide settings, editable from the Settings tab. Stored as a
/// single row (id-less key-value would also work, but a single row
/// is simpler for the handful of fields we have).
class AppSettings {
  final int bufferMinutes;
  final int wakeReminderHour;
  final int wakeReminderMinute;
  final String themeMode; // 'system' | 'light' | 'dark'

  const AppSettings({
    this.bufferMinutes = 10,
    this.wakeReminderHour = 8,
    this.wakeReminderMinute = 0,
    this.themeMode = 'system',
  });

  AppSettings copyWith({
    int? bufferMinutes,
    int? wakeReminderHour,
    int? wakeReminderMinute,
    String? themeMode,
  }) {
    return AppSettings(
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      wakeReminderHour: wakeReminderHour ?? this.wakeReminderHour,
      wakeReminderMinute: wakeReminderMinute ?? this.wakeReminderMinute,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': 0, // single row
      'bufferMinutes': bufferMinutes,
      'wakeReminderHour': wakeReminderHour,
      'wakeReminderMinute': wakeReminderMinute,
      'themeMode': themeMode,
    };
  }

  factory AppSettings.fromMap(Map<String, Object?> map) {
    return AppSettings(
      bufferMinutes: map['bufferMinutes'] as int,
      wakeReminderHour: map['wakeReminderHour'] as int,
      wakeReminderMinute: map['wakeReminderMinute'] as int,
      // Older rows (pre-theme-setting) won't have this column — default
      // to following the system setting, same as before this existed.
      themeMode: map['themeMode'] as String? ?? 'system',
    );
  }
}
