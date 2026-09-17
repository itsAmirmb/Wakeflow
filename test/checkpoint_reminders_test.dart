import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/app_settings.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2099, 1, 10, 10);

  test('checkpoint settings default empty, copy and JSON TEXT round trip', () {
    const empty = AppSettings();
    expect(empty.checkpointMinutesOfDay, isEmpty);
    final legacy = empty.toMap()..remove('checkpointTimes');
    expect(AppSettings.fromMap(legacy).checkpointMinutesOfDay, isEmpty);
    final settings = empty.copyWith(checkpointMinutesOfDay: [900, 720, 900]);
    expect(settings.checkpointMinutesOfDay, [720, 900]);
    expect(settings.toMap()['checkpointTimes'], '[720,900]');
    expect(AppSettings.fromMap(settings.toMap()).checkpointMinutesOfDay, [
      720,
      900,
    ]);
    expect(settings.copyWith(themeMode: 'dark').checkpointMinutesOfDay, [
      720,
      900,
    ]);
    expect(
      settings.copyWith(checkpointMinutesOfDay: []).checkpointMinutesOfDay,
      isEmpty,
    );
    for (final text in ['bad json', '{}', '[null,"x",-1,1440,720,720]']) {
      final parsed = AppSettings.fromMap({...legacy, 'checkpointTimes': text});
      expect(
        parsed.checkpointMinutesOfDay,
        text.startsWith('[') ? [720] : isEmpty,
      );
    }
  });

  test('two fixed times sorted and unique within exact routine boundaries', () {
    expect(
      NotificationService.checkpointOccurrences(
        wakeTime: DateTime(2099, 1, 10, 11),
        dayEnd: DateTime(2099, 1, 10, 18),
        minutesOfDay: [18 * 60, 15 * 60, 11 * 60, 15 * 60, 9 * 60],
        now: now,
      ),
      [DateTime(2099, 1, 10, 11), DateTime(2099, 1, 10, 15)],
    );
    expect(
      NotificationService.checkpointOccurrences(
        wakeTime: now,
        dayEnd: DateTime(2099, 1, 10, 18),
        minutesOfDay: [10 * 60, 12 * 60, 18 * 60],
        now: now,
      ),
      [DateTime(2099, 1, 10, 12)],
    );
  });

  test('midnight crossing uses correct dates and excludes expired times', () {
    final wake = DateTime(2099, 1, 10, 22);
    final end = DateTime(2099, 1, 11, 3);
    expect(
      NotificationService.checkpointOccurrences(
        wakeTime: wake,
        dayEnd: end,
        minutesOfDay: [0, 60, 180, 23 * 60],
        now: now,
      ),
      [
        DateTime(2099, 1, 10, 23),
        DateTime(2099, 1, 11),
        DateTime(2099, 1, 11, 1),
      ],
    );
    expect(
      NotificationService.checkpointOccurrences(
        wakeTime: wake,
        dayEnd: end,
        minutesOfDay: [0, 60, 23 * 60],
        now: DateTime(2099, 1, 11),
      ),
      [DateTime(2099, 1, 11, 1)],
    );
    expect(
      NotificationService.checkpointOccurrences(
        wakeTime: wake,
        dayEnd: end,
        minutesOfDay: [0],
        now: end,
      ),
      isEmpty,
    );
    expect(
      NotificationService.checkpointOccurrences(
        wakeTime: wake,
        dayEnd: wake,
        minutesOfDay: [0],
        now: now,
      ),
      isEmpty,
    );
    expect(
      () => NotificationService.checkpointOccurrences(
        wakeTime: wake,
        dayEnd: end,
        minutesOfDay: [1440],
        now: now,
      ),
      throwsRangeError,
    );
  });

  group('mocked checkpoint plugin', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    late NotificationService service;
    late List<Map<dynamic, dynamic>> scheduled;
    late List<Map<String, Object?>> pending;
    late List<int> cancelled;
    var enabled = true;

    setUp(() {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      scheduled = [];
      pending = [];
      cancelled = [];
      enabled = true;
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
                return false;
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

    Future<void> schedule(String day, List<int> minutes) =>
        service.scheduleCheckpointReminders(
          day: day,
          wakeTime: now,
          dayEnd: DateTime(2099, 1, 10, 18),
          minutesOfDay: minutes,
        );

    test(
      'one-shot payload contains routine and time, IDs avoid all owners',
      () async {
        final when = DateTime(2099, 1, 10, 12);
        final payload = jsonEncode([
          'wakeflow-checkpoint-v1',
          '2099-01-10',
          when.toIso8601String(),
        ]);
        final candidate = NotificationService.blockNotificationId(
          payload,
          end: false,
        );
        for (final id in [0, 1, candidate]) {
          pending.add({
            'id': id,
            'title': 'Existing',
            'body': '',
            'payload': 'other owner',
          });
        }
        await schedule('2099-01-10', [720, 900]);
        expect(scheduled, hasLength(2));
        final ids = scheduled.map((args) => args['id']).toSet();
        expect(ids, hasLength(2));
        expect(ids.intersection({0, 1, candidate}), isEmpty);
        expect(scheduled.first['payload'], payload);
        expect(scheduled.first['timeZoneName'], 'UTC');
        expect(scheduled.first.containsKey('matchDateTimeComponents'), isFalse);
        expect(
          DateTime.parse('${scheduled.first['scheduledDateTime']}Z'),
          when.toUtc(),
        );
        expect(scheduled.first['body'], contains('Open Today'));
        await service.cancelCheckpointReminders(day: '2099-01-10');
        expect(cancelled.toSet(), ids);
        expect(pending.map((request) => request['id']), [0, 1, candidate]);
      },
    );

    test(
      'refresh replaces only routine reminders; cancellation survives restart',
      () async {
        await schedule('first', [720, 900]);
        await schedule('second', [720]);
        final secondId = scheduled.last['id'];
        await schedule('first', [780]);
        expect(pending, hasLength(2));
        expect(cancelled, hasLength(2));
        service = NotificationService.forTesting(
          FlutterLocalNotificationsPlugin(),
          () => now,
        );
        await schedule('first', []);
        expect(pending.single['id'], secondId);
        await service.cancelCheckpointReminders(day: 'second');
        expect(pending, isEmpty);
      },
    );

    test(
      'checkpoint and block scheduling failures propagate and queue recovers',
      () async {
        enabled = false;
        await expectLater(
          schedule('day', [720]),
          throwsA(isA<PlatformException>()),
        );
        await expectLater(
          service.scheduleForBlocks([
            Block(
              id: 'work',
              categoryId: 'work',
              title: 'Work',
              plannedDurationMinutes: 30,
              plannedStart: now.add(const Duration(hours: 1)),
            ),
          ]),
          throwsA(isA<PlatformException>()),
        );
        enabled = true;
        await schedule('day', [720]);
        expect(scheduled, hasLength(1));
      },
    );
  });
}
