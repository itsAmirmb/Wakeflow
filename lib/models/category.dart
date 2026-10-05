class Category {
  final String id;
  final String name;
  final String icon; // emoji for now, no icon package needed
  final double percentage; // 0.0–1.0
  final int minimumMinutes;
  final int preferredBlockMinMinutes;
  final int preferredBlockMaxMinutes;
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
    required this.preferredBlockMinMinutes,
    required this.preferredBlockMaxMinutes,
    this.priority = 0,
    this.enabled = true,
    this.maximumMinutes,
  });

  Category copyWith({
    String? name,
    String? icon,
    double? percentage,
    int? minimumMinutes,
    int? preferredBlockMinMinutes,
    int? preferredBlockMaxMinutes,
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
      preferredBlockMinMinutes:
          preferredBlockMinMinutes ?? this.preferredBlockMinMinutes,
      preferredBlockMaxMinutes:
          preferredBlockMaxMinutes ?? this.preferredBlockMaxMinutes,
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
      'preferredBlockMinMinutes': preferredBlockMinMinutes,
      'preferredBlockMaxMinutes': preferredBlockMaxMinutes,
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
      preferredBlockMinMinutes: map['preferredBlockMinMinutes'] as int,
      preferredBlockMaxMinutes: map['preferredBlockMaxMinutes'] as int,
      priority: map['priority'] as int,
      enabled: (map['enabled'] as int) == 1,
      maximumMinutes: map['maximumMinutes'] as int?,
    );
  }
}