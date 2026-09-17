import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final now = DateTime(2099, 1, 10, 10);
  late NotificationService service;
  late List<Map<dynamic, dynamic>> scheduled;
  late List<Map<String, Object?>> pending;
  late List<int> cancelled;
  var exact = false;
  var enabled = true;
  var rejectExact = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    scheduled = [];
    pending = [];
    cancelled = [];
    exact = false;
    enabled = true;
    rejectExact = false;
    service = NotificationService.forTesting(
      FlutterLocalNotificationsPlugin(),
      () => now,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'areNotificationsEnabled':
              return enabled;
            case 'canScheduleExactNotifications':
              return exact;
            case 'pendingNotificationRequests':
              return pending;
            case 'cancel':
              final id = (call.arguments as Map)['id'] as int;
              cancelled.add(id);
              pending.removeWhere((request) => request['id'] == id);
              return null;
            case 'zonedSchedule':
              final args = Map<dynamic, dynamic>.from(call.arguments as Map);
              scheduled.add(args);
              if (rejectExact &&
                  (args['platformSpecifics'] as Map)['scheduleMode'] ==
                      AndroidScheduleMode.exactAllowWhileIdle.name) {
                throw PlatformException(code: 'exact_alarms_not_permitted');
              }
              pending.removeWhere((request) => request['id'] == args['id']);
              pending.add({
                'id': args['id'],
                'title': args['title'],
                'body': args['body'],
                'payload': args['payload'],
              });
              return null;
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Block block(String id, {BlockStatus status = BlockStatus.pending}) => Block(
    id: id,
    categoryId: 'work',
    title: 'Work',
    plannedDurationMinutes: 30,
    plannedStart: now.add(const Duration(minutes: 10)),
    plannedEnd: now.add(const Duration(minutes: 40)),
    status: status,
    runningSince: status == BlockStatus.active
        ? now.subtract(const Duration(minutes: 5))
        : null,
    accumulatedSeconds: 600,
  );

  test(
    'next occurrence uses local calendar day and validates clock inputs',
    () {
      expect(
        NotificationService.nextLocalWallClockOccurrence(11, 30, now),
        DateTime(2099, 1, 10, 11, 30),
      );
      expect(
        NotificationService.nextLocalWallClockOccurrence(10, 0, now),
        DateTime(2099, 1, 11, 10),
      );
      expect(
        () => NotificationService.nextLocalWallClockOccurrence(24, 0, now),
        throwsRangeError,
      );
    },
  );

  test(
    'wake is one-shot UTC instant and denied exact uses supported mode',
    () async {
      await service.scheduleWakeReminder(hour: 11, minute: 30);
      final args = scheduled.single;
      expect(args['id'], 0);
      expect(args['timeZoneName'], 'UTC');
      expect(args.containsKey('matchDateTimeComponents'), isFalse);
      expect(
        DateTime.parse('${args['scheduledDateTime']}Z'),
        DateTime(2099, 1, 10, 11, 30).toUtc(),
      );
      expect(
        (args['platformSpecifics'] as Map)['scheduleMode'],
        AndroidScheduleMode.inexactAllowWhileIdle.name,
      );
    },
  );

  test('revoked exact permission retries inexact once', () async {
    exact = true;
    rejectExact = true;
    await service.scheduleWakeSnooze();
    expect(scheduled, hasLength(2));
    expect(
      (scheduled.last['platformSpecifics'] as Map)['scheduleMode'],
      AndroidScheduleMode.inexactAllowWhileIdle.name,
    );
  });

  test(
    'denied notification permission reports failure and queue recovers',
    () async {
      enabled = false;
      await expectLater(
        service.scheduleWakeSnooze(),
        throwsA(isA<PlatformException>()),
      );
      expect(scheduled, isEmpty);
      enabled = true;
      await service.scheduleWakeSnooze();
      expect(scheduled, hasLength(1));
    },
  );

  test('Later schedules thirty minutes and replaces snooze only', () async {
    await service.scheduleWakeReminder();
    await service.scheduleWakeSnooze();
    await service.scheduleWakeSnooze();
    expect(scheduled.last['id'], 1);
    expect(
      DateTime.parse('${scheduled.last['scheduledDateTime']}Z'),
      now.add(const Duration(minutes: 30)).toUtc(),
    );
    expect(pending.map((request) => request['id']), [0, 1]);
  });

  test(
    'pending blocks receive start only; active end uses remaining timer',
    () async {
      await service.scheduleForBlocks([
        block('pending'),
        block('active', status: BlockStatus.active),
      ]);
      expect(scheduled, hasLength(1));
      final active = block('active', status: BlockStatus.active);
      expect(
        NotificationService.activeBlockEndAt(active, now),
        now.add(const Duration(minutes: 15)),
      );
      await service.scheduleActiveBlockEnd(active, now: now);
      expect(
        DateTime.parse('${scheduled.last['scheduledDateTime']}Z'),
        now.add(const Duration(minutes: 15)).toUtc(),
      );
      expect(
        NotificationService.activeBlockEndAt(
          block('paused', status: BlockStatus.paused),
          now,
        ),
        isNull,
      );
      expect(
        NotificationService.activeBlockEndAt(
          active,
          now.add(const Duration(hours: 1)),
        ),
        isNull,
      );
    },
  );

  test('IDs are deterministic and start/end occupy disjoint ranges', () {
    expect(
      NotificationService.blockNotificationId('hello', end: false),
      2 + 0x4f9f2cab % 0x3fffffff, // Standard FNV-1a "hello" vector.
    );
    final start = NotificationService.blockNotificationId('شناسه', end: false);
    final end = NotificationService.blockNotificationId('شناسه', end: true);
    expect(start, inInclusiveRange(2, 0x40000000));
    expect(end, inInclusiveRange(0x40000001, 0x7fffffff));
  });

  test(
    'occupied hash is probed and payload cancellation survives restart',
    () async {
      final candidate = NotificationService.blockNotificationId(
        'collision',
        end: false,
      );
      pending.add({
        'id': candidate,
        'title': 'Other',
        'body': '',
        'payload': 'another owner',
      });
      await service.scheduleForBlocks([block('collision')]);
      expect(scheduled.single['id'], isNot(candidate));
      final assigned = scheduled.single['id'];
      service = NotificationService.forTesting(
        FlutterLocalNotificationsPlugin(),
        () => now,
      );
      await service.scheduleForBlocks([block('collision')]);
      expect(scheduled.last['id'], assigned);
      await service.cancelForBlock('collision');
      expect(cancelled, [assigned]);
      expect(pending.single['id'], candidate);
    },
  );
}
