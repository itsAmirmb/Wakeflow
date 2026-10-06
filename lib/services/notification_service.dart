import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/alert_style.dart';
import '../models/block.dart';
import 'database_service.dart';

/// Notification failures propagate to callers so UI can report them without
/// undoing a successfully persisted routine/settings change.
///
/// Wake reminders are ONE SHOT: Dart supplies a device-local DateTime but not a
/// reliable IANA timezone identifier. UTC conversion preserves this occurrence's
/// instant; repeating in UTC or a fixed offset would drift across DST. Refresh
/// on launch/time edits. Without reopening the app there is no daily renewal.
/// Travel/clock changes after scheduling also require reopening the app.
class NotificationService {
  NotificationService._internal()
    : _plugin = FlutterLocalNotificationsPlugin(),
      _now = DateTime.now;

  @visibleForTesting
  NotificationService.forTesting(this._plugin, this._now);

  static final NotificationService instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _now;
  Future<void>? _initialization;
  Future<void> _queue = Future<void>.value();

  static const _channelId = 'wakeflow_blocks';
  static const _channelName = 'Routine Blocks';
  static const _wakeReminderId = 0;
  static const _wakeSnoozeId = 1;
  static const _rangeSize = 0x3fffffff;
  // One break at a time, so one fixed slot (start-range candidates make a
  // clash a one-in-a-billion event; pending IDs are probed anyway).
  static const _breakAlarmId = 2;
  // A repeating alert must never ring forever on an unattended phone.
  static const _alarmTimeoutMs = 180000;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> init() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Block start/end and wake reminders',
          importance: Importance.high,
        ),
      );
    } catch (_) {
      _initialization = null; // Permit a later user action to retry.
      rethrow;
    }
  }

  /// Exact permission is optional: v18 supports inexactAllowWhileIdle without
  /// it. Do not force the user through the special-access settings page.
  Future<void> requestPermissions() async {
    await init();
    await _android?.requestNotificationsPermission();
  }

  // Serialize read/allocate/schedule/cancel so simultaneous UI/startup requests
  // cannot allocate the same vacant slot. A failed operation doesn't poison it.
  Future<void> _serial(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// FNV-1a over UTF-8; start/end use disjoint positive 31-bit ID ranges.
  /// This is a candidate, not a uniqueness guarantee. Pending payloads below
  /// persist collision ownership across process restarts (no database/package).
  @visibleForTesting
  static int blockNotificationId(String blockId, {required bool end}) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(blockId)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return 2 + (end ? _rangeSize : 0) + hash % _rangeSize;
  }

  static String _payload(String blockId, bool end) =>
      jsonEncode(['wakeflow-block-v1', blockId, end ? 'end' : 'start']);

  Future<int> _id(String blockId, {required bool end}) => _allocateId(
    _payload(blockId, end),
    blockNotificationId(blockId, end: end),
    end: end,
  );

  Future<int> _allocateId(
    String payload,
    int candidate, {
    bool end = false,
  }) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (request.payload == payload) return request.id;
    }
    final occupied = pending.map((request) => request.id).toSet();
    final base = end ? 2 + _rangeSize : 2;
    for (var attempts = 0; attempts < _rangeSize; attempts++) {
      if (!occupied.contains(candidate)) return candidate;
      candidate = base + (candidate - base + 1) % _rangeSize;
    }
    throw StateError('Notification ID range exhausted');
  }

  Future<AlertStyle> _styleFor(AlertEvent event) async {
    try {
      return (await DatabaseService.instance.getSettings()).alertFor(event);
    } catch (_) {
      return AlertStyle.defaultFor(event);
    }
  }

  /// Android fixes sound/importance per channel at creation, so every
  /// event + sound + vibration combination gets its own deterministic channel.
  AndroidNotificationDetails _androidDetails(
    AlertEvent? event,
    AlertStyle? style,
  ) {
    if (event == null || style == null) {
      return const AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
      );
    }
    final alarm = style.sound == AlertSound.alarm;
    final silent = style.sound == AlertSound.silent;
    final loop = style.repeat && !silent;
    return AndroidNotificationDetails(
      'wf_${event.name}_${style.sound.name}_${style.vibrate ? 'vib' : 'novib'}',
      'WakeFlow: ${event.label}',
      channelDescription: 'Alerts for: ${event.label}',
      importance: silent
          ? Importance.defaultImportance
          : alarm
          ? Importance.max
          : Importance.high,
      priority: Priority.high,
      playSound: !silent,
      sound: alarm
          ? const UriAndroidNotificationSound(
              'content://settings/system/alarm_alert',
            )
          : null,
      enableVibration: style.vibrate,
      audioAttributesUsage: alarm
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
      category: alarm
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      // FLAG_INSISTENT (4): the sound loops until the notification is opened,
      // swiped away or times out.
      additionalFlags: loop ? Int32List.fromList(<int>[4]) : null,
      timeoutAfter: loop ? _alarmTimeoutMs : null,
    );
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    AlertEvent? event,
  }) async {
    if (!when.isAfter(_now())) return;
    AlertStyle? style;
    if (event != null) {
      style = await _styleFor(event);
      if (!style.enabled) return;
    }
    final android = _android;
    if (await android?.areNotificationsEnabled() == false) {
      throw PlatformException(
        code: 'notifications_denied',
        message: 'Enable notifications in system settings.',
      );
    }
    // Confirmed in v18 source: canScheduleExactNotifications() and
    // AndroidScheduleMode.inexactAllowWhileIdle. Null is conservatively inexact.
    final exact = await android?.canScheduleExactNotifications() == true;
    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.UTC),
      NotificationDetails(android: _androidDetails(event, style)),
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
    try {
      await schedule(
        exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } on PlatformException catch (error) {
      // Permission may be revoked after the capability check. Only retry the
      // plugin's specific exact-permission error, not arbitrary failures.
      if (!exact || error.code != 'exact_alarms_not_permitted') rethrow;
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  /// Planned pending blocks receive START only; end reminders follow the actual
  /// active timer, never a pending block's original planned end.
  Future<void> scheduleForBlocks(List<Block> blocks) => _serial(() async {
    await init();
    for (final block in blocks) {
      if (block.status != BlockStatus.pending ||
          block.plannedStart == null ||
          !block.plannedStart!.isAfter(_now())) {
        continue;
      }
      await _schedule(
        id: await _id(block.id, end: false),
        title: '${block.title} شروع می‌شود',
        body: '${block.plannedDurationMinutes} دقیقه',
        when: block.plannedStart!,
        payload: _payload(block.id, false),
        event: AlertEvent.blockStart,
      );
    }
  });

  Future<void> _cancelBlock(String blockId) async {
    final startPayload = _payload(blockId, false);
    final endPayload = _payload(blockId, true);
    for (final request in await _plugin.pendingNotificationRequests()) {
      if (request.payload == startPayload || request.payload == endPayload) {
        await _plugin.cancel(request.id);
      }
    }
  }

  /// Payload-based lookup also finds collision-probed IDs after a restart and
  /// cannot cancel another block that shares this block's hash candidate.
  Future<void> cancelForBlock(String blockId) => _serial(() async {
    await init();
    await _cancelBlock(blockId);
  });

  Future<void> cancelForBlocks(List<Block> blocks) => _serial(() async {
    await init();
    for (final block in blocks) {
      await _cancelBlock(block.id);
    }
  });

  /// Caller owns start/resume/restore lifecycle. Cancels stale start/end alerts
  /// then schedules the remaining active timer. Pause/complete/skip callers
  /// should use cancelForBlock. Inactive/overdue blocks get no new end alert.
  Future<void> scheduleActiveBlockEnd(Block block, {DateTime? now}) =>
      _serial(() async {
        await init();
        await _cancelBlock(block.id);
        final asOf = now ?? _now();
        final when = activeBlockEndAt(block, asOf);
        if (when == null) return;
        await _schedule(
          id: await _id(block.id, end: true),
          title: '${block.title} تمام شد',
          body: 'وقت رفتن به بلاک بعدی است',
          when: when,
          payload: _payload(block.id, true),
          event: AlertEvent.blockEnd,
        );
      });

  @visibleForTesting
  static DateTime? activeBlockEndAt(Block block, DateTime now) {
    if (block.status != BlockStatus.active || block.runningSince == null) {
      return null;
    }
    final elapsed = block.elapsedAt(now);
    final remaining =
        Duration(minutes: block.plannedDurationMinutes) -
        (elapsed.isNegative ? Duration.zero : elapsed);
    return remaining > Duration.zero ? now.add(remaining) : null;
  }

  /// Future local clock occurrences in this routine, including wake time but
  /// excluding now and the deadline. Calendar construction handles midnight
  /// and uses the device's offset at each target date (not fixed 24h jumps).
  @visibleForTesting
  static List<DateTime> checkpointOccurrences({
    required DateTime wakeTime,
    required DateTime dayEnd,
    required List<int> minutesOfDay,
    required DateTime now,
  }) {
    final minutes = minutesOfDay.toSet().toList()..sort();
    for (final minute in minutes) {
      RangeError.checkValueInInterval(minute, 0, 1439, 'minutesOfDay');
    }
    final wake = wakeTime.toLocal();
    final end = dayEnd.toLocal();
    final occurrences = <DateTime>[];
    if (minutes.isEmpty || !end.isAfter(wake)) return occurrences;
    var date = DateTime(wake.year, wake.month, wake.day);
    while (date.isBefore(end)) {
      for (final minute in minutes) {
        final when = DateTime(
          date.year,
          date.month,
          date.day,
          minute ~/ 60,
          minute % 60,
        );
        if (!when.isBefore(wake) && when.isAfter(now) && when.isBefore(end)) {
          occurrences.add(when);
        }
      }
      date = DateTime(date.year, date.month, date.day + 1);
    }
    // DST clock normalization can map two wall times onto one instant.
    return occurrences.toSet().toList()..sort();
  }

  static const _checkpointPayloadTag = 'wakeflow-checkpoint-v1';

  Future<void> _cancelCheckpoints(String day) =>
      _cancelTagged(_checkpointPayloadTag, day);

  Future<void> _cancelTagged(String tag, String day) async {
    for (final request in await _plugin.pendingNotificationRequests()) {
      final payload = request.payload;
      if (payload == null) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        continue;
      }
      if (decoded is List &&
          decoded.length == 3 &&
          decoded[0] == tag &&
          decoded[1] == day) {
        await _plugin.cancel(request.id);
      }
    }
  }

  /// Replaces reminders for this routine only, including removing stale times
  /// when the list is empty or the routine is over. Other routines, block and
  /// wake reminders are untouched. Errors propagate after persistence succeeds.
  /// IDs share the collision-checked allocator; no existing pending ID is reused
  /// unless its complete payload matches. Each payload carries day and ISO time.
  Future<void> scheduleCheckpointReminders({
    required String day,
    required DateTime wakeTime,
    required DateTime dayEnd,
    required List<int> minutesOfDay,
  }) => _serial(() async {
    final occurrences = checkpointOccurrences(
      wakeTime: wakeTime,
      dayEnd: dayEnd,
      minutesOfDay: minutesOfDay,
      now: _now(),
    );
    await init();
    await _cancelCheckpoints(day);
    for (final when in occurrences) {
      final payload = jsonEncode([
        _checkpointPayloadTag,
        day,
        when.toIso8601String(),
      ]);
      await _schedule(
        id: await _allocateId(
          payload,
          blockNotificationId(payload, end: false),
        ),
        title: 'Checkpoint reminder',
        body: 'Open Today to review your progress.',
        when: when,
        payload: payload,
        event: AlertEvent.checkpoint,
      );
    }
  });

  static const _commitmentPayloadTag = 'wakeflow-commitment-v1';
  static const _commitmentLeadMinutes = 10;

  /// Reminds shortly before each fixed commitment of this routine day starts.
  /// Replaces only this day's commitment reminders.
  Future<void> scheduleCommitmentReminders({
    required String day,
    required List<({String title, DateTime start})> items,
  }) => _serial(() async {
    await init();
    await _cancelTagged(_commitmentPayloadTag, day);
    for (final item in items) {
      final payload = jsonEncode([
        _commitmentPayloadTag,
        day,
        item.start.toIso8601String(),
      ]);
      final hh = item.start.hour.toString().padLeft(2, '0');
      final mm = item.start.minute.toString().padLeft(2, '0');
      await _schedule(
        id: await _allocateId(
          payload,
          blockNotificationId(payload, end: false),
        ),
        title: 'Coming up: ${item.title}',
        body: 'Starts at $hh:$mm',
        when: item.start.subtract(const Duration(minutes: _commitmentLeadMinutes)),
        payload: payload,
        event: AlertEvent.commitment,
      );
    }
  });

  Future<void> cancelCheckpointReminders({required String day}) =>
      _serial(() async {
        await init();
        await _cancelCheckpoints(day);
      });

  /// Alarm-style alert when a break ends. Replaces any earlier one; the
  /// default style loops its sound (bounded) until the user reacts.
  Future<void> scheduleBreakEnd({
    required DateTime when,
    required String nextTitle,
  }) => _serial(() async {
    await init();
    await _plugin.cancel(_breakAlarmId);
    await _schedule(
      id: _breakAlarmId,
      title: 'Break over',
      body: 'Time to start $nextTitle',
      when: when,
      payload: jsonEncode(['wakeflow-break-v1']),
      event: AlertEvent.breakEnd,
    );
  });

  /// Cancels a pending break alert and silences one that is already ringing.
  Future<void> cancelBreakAlarm() => _serial(() async {
    await init();
    await _plugin.cancel(_breakAlarmId);
  });

  /// Next occurrence only, renewed on launch or wake-time edit. No UTC repeat:
  /// a device IANA zone/native timezone integration is needed for true daily
  /// local wall-clock scheduling while closed, including DST/travel handling.
  Future<void> scheduleWakeReminder({int hour = 8, int minute = 0}) =>
      _serial(() async {
        await init();
        await _schedule(
          id: _wakeReminderId,
          title: 'Ready to start your day?',
          body: 'Tap to plan your day',
          when: nextLocalWallClockOccurrence(hour, minute, _now()),
        );
      });

  /// A separate fixed ID replaces the previous snooze, not the wake reminder.
  Future<void> scheduleWakeSnooze() => _serial(() async {
    await init();
    await _schedule(
      id: _wakeSnoozeId,
      title: 'Ready to start your day?',
      body: 'Tap to plan your day',
      when: _now().add(const Duration(minutes: 30)),
    );
  });

  Future<void> cancelWakeSnooze() => _serial(() async {
    await init();
    await _plugin.cancel(_wakeSnoozeId);
  });

  @visibleForTesting
  static DateTime nextLocalWallClockOccurrence(
    int hour,
    int minute,
    DateTime now,
  ) {
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    RangeError.checkValueInInterval(minute, 0, 59, 'minute');
    final local = now.toLocal();
    var when = DateTime(local.year, local.month, local.day, hour, minute);
    if (!when.isAfter(local)) {
      // Calendar tomorrow, NOT +24 hours: the device applies the offset at the
      // target date, including a DST transition between today and tomorrow.
      when = DateTime(local.year, local.month, local.day + 1, hour, minute);
    }
    return when;
  }
}
