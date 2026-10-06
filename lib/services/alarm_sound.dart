import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// In-app sounds on Android's ALARM audio stream (see MainActivity). Sounds
/// are bundled in res/raw, so they never depend on the phone's own tones or
/// on notification-channel settings. Loops auto-stop natively after 3 minutes.
class AlarmSound {
  static const _channel = MethodChannel('org.amirmb.wakeflow/alarm');

  /// [sound] is a res/raw file name without extension.
  static Future<void> play(String sound, {bool loop = false}) =>
      _invoke('play', {'sound': sound, 'loop': loop});

  static Future<void> stop() => _invoke('stop');

  static Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (error) {
      debugPrint('AlarmSound.$method failed: $error');
    }
  }
}
