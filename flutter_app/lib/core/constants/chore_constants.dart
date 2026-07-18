import 'package:flutter/material.dart';

/// Single source of truth for chore category/effort metadata.
///
/// These used to be duplicated (and drifting) between `chore_model.dart` and
/// `create_chore_screen.dart` — see TASK-065. Where the two disagreed, the
/// `create_chore_screen` wording won since it's the more descriptive one
/// shown to admins while creating a chore.

/// Icon shown for each category key.
const Map<String, IconData> categoryIcons = {
  'kitchen': Icons.kitchen,
  'bathroom': Icons.bathroom,
  'bedroom': Icons.bed,
  'living_room': Icons.weekend,
  'laundry_room': Icons.local_laundry_service,
  'garden_outdoor': Icons.yard,
  'garage': Icons.garage,
  'other_general': Icons.home_repair_service,
};

/// Human-readable label for each category key.
const Map<String, String> categoryLabels = {
  'kitchen': 'Kitchen',
  'bathroom': 'Bathroom',
  'bedroom': 'Bedroom',
  'living_room': 'Living Room',
  'laundry_room': 'Laundry Room',
  'garden_outdoor': 'Garden / Outdoor',
  'garage': 'Garage',
  'other_general': 'Other / General',
};

/// Accent color for each category key (used for the small dot on chore cards).
const Map<String, Color> categoryColors = {
  'kitchen': Color(0xFF14B8A6),
  'bathroom': Color(0xFF0EA5E9),
  'bedroom': Color(0xFF8B5CF6),
  'living_room': Color(0xFF8B5CF6),
  'laundry_room': Color(0xFF0EA5E9),
  'garden_outdoor': Color(0xFF22C55E),
  'garage': Color(0xFF6B7280),
  'other_general': Color(0xFF9CA3AF),
};

/// Label + points awarded for each effort-level key.
const Map<String, ({String label, int points})> effortLevels = {
  'easy': (label: 'Easy', points: 10),
  'medium': (label: 'Medium', points: 25),
  'hard': (label: 'Hard', points: 50),
};

/// Points awarded for [effortLevel], falling back to the "easy" value for an
/// unrecognized key.
int effortPointsFor(String effortLevel) =>
    effortLevels[effortLevel]?.points ?? effortLevels['easy']!.points;

/// Human-readable label for recurrence interval units.
const Map<String, String> intervalUnitLabels = {
  'days': 'Days',
  'weeks': 'Weeks',
  'months': 'Months',
};
