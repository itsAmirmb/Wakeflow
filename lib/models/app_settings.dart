import 'dart:convert';

import 'alert_style.dart';

/// How the distillation keep-threshold is expressed.
enum DistillKeepMode { minutes, percent }

/// App-wide settings, editable from the Settings tab. Stored as a
/// single row (id-less key-value would also work, but a single row
/// is simpler for the handful of fields we have).
class AppSettings {
  final int bufferMinutes;

  /// Break after the LAST block of a category (the category is finished).
  final int longBreakMinutes;

  /// Phone alarm chosen for the end of a break (null = bundled default).
  final String? breakAlarmUri;
  final String? breakAlarmTitle;
  final int wakeReminderHour;
  final int wakeReminderMinute;
  final String themeMode; // 'system' | 'light' | 'dark'
  final List<int> checkpointMinutesOfDay;

  /// Distillation keeps an unfinished block as a partial session when its
  /// progress reaches this threshold; below it, the block is discarded and
  /// re-planned. 0 means any recorded progress is kept.
  final DistillKeepMode distillKeepMode;
  final int distillKeepValue; // minutes, or percent of the block (0-100)

  /// Minutes after midnight at which a new day starts (default 04:00).
  final int dayResetMinutes;

  /// Per-event alert styles; events not listed use [AlertStyle.defaultFor].
  final Map<AlertEvent, AlertStyle> alerts;

  const AppSettings({
    this.bufferMinutes = 10,
    this.longBreakMinutes = 30,
    this.breakAlarmUri,
    this.breakAlarmTitle,
    this.wakeReminderHour = 8,
    this.wakeReminderMinute = 0,
    this.themeMode = 'system',
    this.checkpointMinutesOfDay = const [],
    this.distillKeepMode = DistillKeepMode.minutes,
    this.distillKeepValue = 5,
    this.dayResetMinutes = 240,
    this.alerts = const {},
  });

  AlertStyle alertFor(AlertEvent event) =>
      alerts[event] ?? AlertStyle.defaultFor(event);

  AppSettings copyWith({
    int? bufferMinutes,
    int? longBreakMinutes,
    String? breakAlarmUri,
    String? breakAlarmTitle,
    bool clearBreakAlarm = false,
    int? wakeReminderHour,
    int? wakeReminderMinute,
    String? themeMode,
    List<int>? checkpointMinutesOfDay,
    DistillKeepMode? distillKeepMode,
    int? distillKeepValue,
    int? dayResetMinutes,
    Map<AlertEvent, AlertStyle>? alerts,
  }) {
    return AppSettings(
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
      breakAlarmUri: clearBreakAlarm
          ? null
          : (breakAlarmUri ?? this.breakAlarmUri),
      breakAlarmTitle: clearBreakAlarm
          ? null
          : (breakAlarmTitle ?? this.breakAlarmTitle),
      wakeReminderHour: wakeReminderHour ?? this.wakeReminderHour,
      wakeReminderMinute: wakeReminderMinute ?? this.wakeReminderMinute,
      themeMode: themeMode ?? this.themeMode,
      checkpointMinutesOfDay: _normalizeCheckpoints(
        checkpointMinutesOfDay ?? this.checkpointMinutesOfDay,
      ),
      distillKeepMode: distillKeepMode ?? this.distillKeepMode,
      distillKeepValue: distillKeepValue ?? this.distillKeepValue,
      dayResetMinutes: dayResetMinutes ?? this.dayResetMinutes,
      alerts: alerts ?? this.alerts,
    );
  }

  /// Progress a block of [plannedMinutes] needs before it counts as real
  /// work. Never more than the block's own duration, so short blocks can
  /// always reach it.
  Duration keepThreshold(int plannedMinutes) {
    final planned = Duration(minutes: plannedMinutes);
    final raw = distillKeepMode == DistillKeepMode.minutes
        ? Duration(minutes: distillKeepValue)
        : Duration(
            seconds: (plannedMinutes * 60 * distillKeepValue / 100).ceil(),
          );
    return raw > planned ? planned : raw;
  }

  /// True when [elapsed] on a block of [plannedMinutes] reached the keep
  /// threshold. Used both to unlock DONE and to decide what Distill keeps.
  bool isProgressKept({
    required Duration elapsed,
    required int plannedMinutes,
  }) {
    if (elapsed.inSeconds <= 0) return false;
    return elapsed.inSeconds >= keepThreshold(plannedMinutes).inSeconds;
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
      'longBreakMinutes': longBreakMinutes,
      'breakAlarmUri': breakAlarmUri,
      'breakAlarmTitle': breakAlarmTitle,
      'wakeReminderHour': wakeReminderHour,
      'wakeReminderMinute': wakeReminderMinute,
      'themeMode': themeMode,
      'checkpointTimes': jsonEncode(
        _normalizeCheckpoints(checkpointMinutesOfDay),
      ),
      'distillKeepMode': distillKeepMode.name,
      'distillKeepValue': distillKeepValue,
      'dayResetMinutes': dayResetMinutes,
      'alerts': jsonEncode({
        for (final e in alerts.entries) e.key.name: e.value.toJson(),
      }),
    };
  }

  factory AppSettings.fromMap(Map<String, Object?> map) {
    return AppSettings(
      bufferMinutes: map['bufferMinutes'] as int,
      longBreakMinutes: ((map['longBreakMinutes'] as int?) ?? 30).clamp(0, 180),
      breakAlarmUri: map['breakAlarmUri'] as String?,
      breakAlarmTitle: map['breakAlarmTitle'] as String?,
      wakeReminderHour: map['wakeReminderHour'] as int,
      wakeReminderMinute: map['wakeReminderMinute'] as int,
      // Older rows (pre-theme-setting) won't have this column — default
      // to following the system setting, same as before this existed.
      themeMode: map['themeMode'] as String? ?? 'system',
      // Older rows have no checkpoint times; do not invent default reminders.
      checkpointMinutesOfDay: _parseCheckpoints(
        map['checkpointTimes'] as String?,
      ),
      distillKeepMode: DistillKeepMode.values.firstWhere(
        (m) => m.name == map['distillKeepMode'],
        orElse: () => DistillKeepMode.minutes,
      ),
      distillKeepValue: map['distillKeepValue'] as int? ?? 5,
      dayResetMinutes: ((map['dayResetMinutes'] as int?) ?? 240).clamp(0, 1439),
      alerts: _parseAlerts(map['alerts']),
    );
  }

  static Map<AlertEvent, AlertStyle> _parseAlerts(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final event in AlertEvent.values)
          if (decoded[event.name] is Map)
            event: AlertStyle.fromJson(
              Map<String, Object?>.from(decoded[event.name] as Map),
              AlertStyle.defaultFor(event),
            ),
      };
    } catch (_) {
      return const {};
    }
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
