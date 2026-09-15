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
  });
}