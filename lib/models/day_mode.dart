enum DayMode { early, normal, late, emergency }

extension DayModeLabel on DayMode {
  String get label {
    switch (this) {
      case DayMode.early:
        return 'EARLY';
      case DayMode.normal:
        return 'NORMAL';
      case DayMode.late:
        return 'LATE';
      case DayMode.emergency:
        return 'EMERGENCY';
    }
  }
}