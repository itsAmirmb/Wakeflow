import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// In-app sounds on Android's ALARM audio stream (see MainActivity). Sounds
/// are bundled in res/raw; an optional phone alarm [uri] overrides [sound]
/// (and falls back to it if the phone's file cannot be played). Loops
/// auto-stop natively after 3 minutes.
class AlarmSound {
  static const _channel = MethodChannel('org.amirmb.wakeflow/alarm');

  /// [sound] is a res/raw file name without extension.
  static Future<void> play(String sound, {bool loop = false, String? uri}) =>
      _invoke('play', {'sound': sound, 'loop': loop, 'uri': uri});

  static Future<void> stop() => _invoke('stop');

  /// Opens the phone's alarm-sound picker. Null when cancelled.
  static Future<({String uri, String title})?> pickAlarm({
    String? current,
  }) async {
    try {
      final map = await _channel.invokeMapMethod<String, String>(
        'pickAlarm',
        {'current': current},
      );
      final uri = map?['uri'];
      if (uri == null) return null;
      return (uri: uri, title: map?['title'] ?? 'Alarm');
    } catch (error) {
      debugPrint('AlarmSound.pickAlarm failed: $error');
      return null;
    }
  }

  static Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (error) {
      debugPrint('AlarmSound.$method failed: $error');
    }
  }
}
