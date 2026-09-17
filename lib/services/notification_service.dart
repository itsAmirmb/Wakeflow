import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/block.dart';

/// Wraps flutter_local_notifications for WakeFlow's three notification
/// kinds: Block Start, Block End, and the daily Wake Check reminder.
///
/// Notification IDs are derived deterministically from the block id
/// (start/end) so they can be cancelled individually when a block's
/// time changes (checkpoint) or when the user completes/skips it
/// manually before its End notification would have fired.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'wakeflow_blocks';
  static const _channelName = 'Routine Blocks';

  // Fixed offset added to a block's own hash so start/end notifications
  // for the same block never collide with each other or with the wake
  // reminder's fixed id (0).
  static const _startIdOffset = 1000000;
  static const _endIdOffset = 2000000;
  static const _wakeReminderId = 0;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    // No timezone plugin is wired in (keeps this phase minimal per the
    // "no unnecessary dependencies" rule) — local device time is used
    // via tz.local's default, which falls back to UTC. This is fine
    // for a same-device, local-only routine app; revisit if the app
    // ever needs to be timezone-aware across devices.
    tz.setLocalLocation(tz.getLocation('UTC'));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Block start/end and wake reminders',
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  /// Requests the runtime permissions needed on Android 13+ (POST_NOTIFICATIONS)
  /// and Android 12+ (exact alarms). Call once, e.g. right after init()
  /// from main() or the first screen — safe to call repeatedly.
  Future<void> requestPermissions() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  int _startId(String blockId) => _startIdOffset + blockId.hashCode.abs() % 900000;
  int _endId(String blockId) => _endIdOffset + blockId.hashCode.abs() % 900000;

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    // Don't schedule notifications for times that have already passed
    // (can happen after a checkpoint recalculation for the tail end
    // of blocks that started before now).
    if (when.isBefore(DateTime.now())) return;

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedules Start and End notifications for every block that still
  /// has a pending status and a planned time (skips already-finished
  /// blocks). Call after generating a fresh routine or after a
  /// checkpoint recalculation.
  Future<void> scheduleForBlocks(List<Block> blocks) async {
    for (final block in blocks) {
      if (block.status != BlockStatus.pending) continue;
      if (block.plannedStart != null) {
        await _schedule(
          id: _startId(block.id),
          title: '${block.title} شروع می‌شود',
          body: '${block.plannedDurationMinutes} دقیقه',
          when: block.plannedStart!,
        );
      }
      if (block.plannedEnd != null) {
        await _schedule(
          id: _endId(block.id),
          title: '${block.title} تمام شد',
          body: 'وقت رفتن به بلاک بعدی است',
          when: block.plannedEnd!,
        );
      }
    }
  }

  /// Cancels both Start and End notifications for a single block.
  /// Call when a block is manually started/paused/completed/skipped,
  /// so a stale notification doesn't fire after the fact.
  Future<void> cancelForBlock(String blockId) async {
    await _plugin.cancel(_startId(blockId));
    await _plugin.cancel(_endId(blockId));
  }

  /// Cancels Start/End notifications for a whole list of blocks —
  /// used before re-scheduling after a checkpoint recalculation.
  Future<void> cancelForBlocks(List<Block> blocks) async {
    for (final block in blocks) {
      await cancelForBlock(block.id);
    }
  }

  /// Schedules the daily "بیدار شدی؟" reminder at [hour]:[minute],
  /// repeating every day. Re-scheduling replaces the previous one.
  Future<void> scheduleWakeReminder({int hour = 8, int minute = 0}) async {
    final now = DateTime.now();
    var when = DateTime(now.year, now.month, now.day, hour, minute);
    if (when.isBefore(now)) {
      when = when.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      _wakeReminderId,
      'بیدار شدی؟',
      'برای شروع روز ضربه بزن',
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repeats daily
    );
  }
}
