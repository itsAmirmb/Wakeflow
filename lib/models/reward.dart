import 'package:flutter/material.dart';

/// Something credits can be spent on. Add entries to [kRewards] to offer more.
class Reward {
  final String id;
  final String title;
  final String description;
  final int costCredits;
  final IconData icon;

  const Reward({
    required this.id,
    required this.title,
    required this.description,
    required this.costCredits,
    required this.icon,
  });
}

const List<Reward> kRewards = [
  Reward(
    id: 'movie_60',
    title: 'Movie time',
    description: '60 minutes of a movie',
    costCredits: 60,
    icon: Icons.movie_outlined,
  ),
];
