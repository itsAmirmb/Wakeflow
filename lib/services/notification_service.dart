import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/block.dart';

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

  Future<int> _id(String blockId, {required bool end}) async {
    final pending = await _plugin.pendingNotificationRequests();
    final payload = _payload(blockId, end);
    for (final request in pending) {
      if (request.payload == payload) return request.id;
    }
    final occupied = pending.map((request) => request.id).toSet();
    final base = end ? 2 + _rangeSize : 2;
    var candidate = blockNotificationId(blockId, end: end);
    for (var attempts = 0; attempts < _rangeSize; attempts++) {
      if (!occupied.contains(candidate)) return candidate;
      candidate = base + (candidate - base + 1) % _rangeSize;
    }
    throw StateError('Notification ID range exhausted');
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (!when.isAfter(_now())) return;
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
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
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

  /// Next occurrence only, renewed on launch or wake-time edit. No UTC repeat:
  /// a device IANA zone/native timezone integration is needed for true daily
  /// local wall-clock scheduling while closed, including DST/travel handling.
  Future<void> scheduleWakeReminder({int hour = 8, int minute = 0}) =>
      _serial(() async {
        await init();
        await _schedule(
          id: _wakeReminderId,
          title: 'بیدار شدی؟',
          body: 'برای شروع روز ضربه بزن',
          when: nextLocalWallClockOccurrence(hour, minute, _now()),
        );
      });

  /// A separate fixed ID replaces the previous snooze, not the wake reminder.
  Future<void> scheduleWakeSnooze() => _serial(() async {
    await init();
    await _schedule(
      id: _wakeSnoozeId,
      title: 'بیدار شدی؟',
      body: 'برای شروع روز ضربه بزن',
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
