import '../models/category.dart';

final List<Category> defaultCategories = [
  const Category(
    id: 'academic',
    name: 'Academic',
    icon: '📚',
    percentage: 0.40,
    minimumMinutes: 60,
    preferredBlockMinMinutes: 60,
    preferredBlockMaxMinutes: 90,
    priority: 1,
  ),
  const Category(
    id: 'trading',
    name: 'Trading',
    icon: '📈',
    percentage: 0.25,
    minimumMinutes: 30,
    preferredBlockMinMinutes: 45,
    preferredBlockMaxMinutes: 90,
    priority: 2,
  ),
  const Category(
    id: 'gym_fun',
    name: 'Gym / Fun',
    icon: '🏋️',
    percentage: 0.35,
    minimumMinutes: 60,
    preferredBlockMinMinutes: 30,
    preferredBlockMaxMinutes: 120,
    priority: 3,
  ),
];