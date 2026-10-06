import 'package:flutter/material.dart';
import '../models/category.dart';

class CategoryCard extends StatelessWidget {
  final Category category;

  const CategoryCard({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: ListTile(
        leading: Text(category.icon, style: const TextStyle(fontSize: 24)),
        title: Text(category.name),
        subtitle: Text(
          '${(category.percentage * 100).round()}% · '
          '${category.blockMinutes}m blocks',
        ),
      ),
    );
  }
}