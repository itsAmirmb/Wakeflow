import '../models/category.dart';

final List<Category> defaultCategories = [
  const Category(
    id: 'academic',
    name: 'Academic',
    icon: '📚',
    percentage: 0.40,
    minimumMinutes: 60,
    blockMinutes: 60,
    priority: 1,
  ),
  const Category(
    id: 'trading',
    name: 'Trading',
    icon: '📈',
    percentage: 0.25,
    minimumMinutes: 30,
    blockMinutes: 45,
    priority: 2,
  ),
  const Category(
    id: 'gym_fun',
    name: 'Gym / Fun',
    icon: '🏋️',
    percentage: 0.35,
    minimumMinutes: 60,
    blockMinutes: 30,
    priority: 3,
  ),
];