class Category {
  final String id;
  final String name;
  final String icon; // emoji for now, no icon package needed
  final double percentage; // 0.0–1.0
  final int minimumMinutes;

  /// Target block size. The day's time for this category is split evenly
  /// into the number of blocks that comes closest to this length (see
  /// RoutineEngine), so blocks are around this size, not exactly it.
  final int blockMinutes;
  final int priority;
  final bool enabled;

  /// Most minutes per day this category may take (credited work included).
  /// null means no limit; time it cannot take is simply left unplanned.
  final int? maximumMinutes;

  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.percentage,
    required this.minimumMinutes,
    required this.blockMinutes,
    this.priority = 0,
    this.enabled = true,
    this.maximumMinutes,
  });

  Category copyWith({
    String? name,
    String? icon,
    double? percentage,
    int? minimumMinutes,
    int? blockMinutes,
    int? priority,
    bool? enabled,
    int? maximumMinutes,
    bool clearMaximum = false,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      percentage: percentage ?? this.percentage,
      minimumMinutes: minimumMinutes ?? this.minimumMinutes,
      blockMinutes: blockMinutes ?? this.blockMinutes,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
      maximumMinutes: clearMaximum
          ? null
          : (maximumMinutes ?? this.maximumMinutes),
    );
  }

  // SQLite stores bool as 0/1, so enabled is converted explicitly.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'percentage': percentage,
      'minimumMinutes': minimumMinutes,
      // The table still has the old min/max columns (NOT NULL), so the one
      // fixed size is stored in both; it is read back from the first.
      'preferredBlockMinMinutes': blockMinutes,
      'preferredBlockMaxMinutes': blockMinutes,
      'priority': priority,
      'enabled': enabled ? 1 : 0,
      'maximumMinutes': maximumMinutes,
    };
  }

  factory Category.fromMap(Map<String, Object?> map) {
    return Category(
      id: map['id'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String,
      percentage: map['percentage'] as double,
      minimumMinutes: map['minimumMinutes'] as int,
      blockMinutes: map['preferredBlockMinMinutes'] as int,
      priority: map['priority'] as int,
      enabled: (map['enabled'] as int) == 1,
      maximumMinutes: map['maximumMinutes'] as int?,
    );
  }
}