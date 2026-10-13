import '../models/category.dart';

/// A fresh install starts with one category; more can be added in Settings.
final List<Category> defaultCategories = [
  const Category(
    id: 'daily_routine',
    name: 'Daily Routine',
    icon: '🗓️',
    percentage: 1.0,
    minimumMinutes: 60,
    blockMinutes: 60,
    priority: 1,
  ),
];
