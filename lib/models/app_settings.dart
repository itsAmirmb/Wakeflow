import 'dart:convert';

/// App-wide settings, editable from the Settings tab. Stored as a
/// single row (id-less key-value would also work, but a single row
/// is simpler for the handful of fields we have).
class AppSettings {
  final int bufferMinutes;
  final int wakeReminderHour;
  final int wakeReminderMinute;
  final String themeMode; // 'system' | 'light' | 'dark'
  final List<int> checkpointMinutesOfDay;

  const AppSettings({
    this.bufferMinutes = 10,
    this.wakeReminderHour = 8,
    this.wakeReminderMinute = 0,
    this.themeMode = 'system',
    this.checkpointMinutesOfDay = const [],
  });

  AppSettings copyWith({
    int? bufferMinutes,
    int? wakeReminderHour,
    int? wakeReminderMinute,
    String? themeMode,
    List<int>? checkpointMinutesOfDay,
  }) {
    return AppSettings(
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      wakeReminderHour: wakeReminderHour ?? this.wakeReminderHour,
      wakeReminderMinute: wakeReminderMinute ?? this.wakeReminderMinute,
      themeMode: themeMode ?? this.themeMode,
      checkpointMinutesOfDay: _normalizeCheckpoints(
        checkpointMinutesOfDay ?? this.checkpointMinutesOfDay,
      ),
    );
  }

  /// Ignore invalid stored entries and keep clock times unique and sorted.
  static List<int> _normalizeCheckpoints(Iterable<Object?> minutes) {
    final valid = minutes
        .whereType<int>()
        .where((m) => m >= 0 && m < 1440)
        .toSet();
    return valid.toList()..sort();
  }

  Map<String, Object?> toMap() {
    return {
      'id': 0, // single row
      'bufferMinutes': bufferMinutes,
      'wakeReminderHour': wakeReminderHour,
      'wakeReminderMinute': wakeReminderMinute,
      'themeMode': themeMode,
      'checkpointTimes': jsonEncode(
        _normalizeCheckpoints(checkpointMinutesOfDay),
      ),
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
      // Older rows have no checkpoint times; do not invent default reminders.
      checkpointMinutesOfDay: _parseCheckpoints(
        map['checkpointTimes'] as String?,
      ),
    );
  }

  static List<int> _parseCheckpoints(String? text) {
    if (text == null || text.isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      return decoded is List
          ? _normalizeCheckpoints(decoded.cast<Object?>())
          : const [];
    } on FormatException {
      return const [];
    }
  }
}
