/// Events the app can alert about. Each has its own sound/vibration style.
enum AlertEvent { blockStart, blockEnd, breakEnd, checkpoint }

enum AlertSound { standard, alarm, silent }

extension AlertEventLabel on AlertEvent {
  String get label => switch (this) {
    AlertEvent.blockStart => 'Block starts',
    AlertEvent.blockEnd => 'Block ends',
    AlertEvent.breakEnd => 'Break ends',
    AlertEvent.checkpoint => 'Checkpoint reminder',
  };
}

/// How one kind of alert behaves. [repeat] makes the sound loop (alarm-like)
/// until the notification is opened or swiped away, with a hard time limit.
class AlertStyle {
  final bool enabled;
  final AlertSound sound;
  final bool vibrate;
  final bool repeat;

  const AlertStyle({
    this.enabled = true,
    this.sound = AlertSound.standard,
    this.vibrate = true,
    this.repeat = false,
  });

  /// The end of a break is the one alert that must not be missed.
  static AlertStyle defaultFor(AlertEvent event) => event == AlertEvent.breakEnd
      ? const AlertStyle(sound: AlertSound.alarm, repeat: true)
      : const AlertStyle();

  AlertStyle copyWith({
    bool? enabled,
    AlertSound? sound,
    bool? vibrate,
    bool? repeat,
  }) => AlertStyle(
    enabled: enabled ?? this.enabled,
    sound: sound ?? this.sound,
    vibrate: vibrate ?? this.vibrate,
    repeat: repeat ?? this.repeat,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'sound': sound.name,
    'vibrate': vibrate,
    'repeat': repeat,
  };

  factory AlertStyle.fromJson(Map<String, Object?> json, AlertStyle fallback) =>
      AlertStyle(
        enabled: json['enabled'] as bool? ?? fallback.enabled,
        sound: AlertSound.values.firstWhere(
          (s) => s.name == json['sound'],
          orElse: () => fallback.sound,
        ),
        vibrate: json['vibrate'] as bool? ?? fallback.vibrate,
        repeat: json['repeat'] as bool? ?? fallback.repeat,
      );
}
