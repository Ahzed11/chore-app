import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const categoryIcons = {
  'kitchen': Icons.kitchen,
  'bathroom': Icons.bathroom,
  'bedroom': Icons.bed,
  'living_room': Icons.weekend,
  'laundry_room': Icons.local_laundry_service,
  'garden_outdoor': Icons.yard,
  'garage': Icons.garage,
  'other_general': Icons.home_repair_service,
};

const categoryLabels = {
  'kitchen': 'Kitchen',
  'bathroom': 'Bathroom',
  'bedroom': 'Bedroom',
  'living_room': 'Living Room',
  'laundry_room': 'Laundry',
  'garden_outdoor': 'Garden',
  'garage': 'Garage',
  'other_general': 'Other',
};

/// Points awarded per effort level.
const effortPoints = {
  'easy': 10,
  'medium': 25,
  'hard': 50,
};

// ---------------------------------------------------------------------------
// ChoreModel
// ---------------------------------------------------------------------------

class ChoreModel {
  const ChoreModel({
    required this.id,
    required this.definitionId,
    required this.householdId,
    this.assigneeId,
    this.assigneeName,
    required this.assignedManually,
    required this.dueDate,
    required this.status,
    this.completedAt,
    this.pointsAwarded,
    required this.title,
    this.description,
    required this.category,
    required this.effortLevel,
    required this.choreType,
  });

  final String id;
  final String definitionId;
  final String householdId;
  final String? assigneeId;
  final String? assigneeName;
  final bool assignedManually;
  final DateTime dueDate;
  final String status; // pending | complete | overdue | cancelled
  final DateTime? completedAt;
  final int? pointsAwarded;
  final String title;
  final String? description;
  final String category;
  final String effortLevel; // easy | medium | hard
  final String choreType; // one_off | recurring

  // ---------------------------------------------------------------------------
  // Derived getters
  // ---------------------------------------------------------------------------

  /// True when the status is "overdue" or the due date has passed for a pending
  /// chore (client-side safety net).
  bool get isOverdue =>
      status == 'overdue' ||
      (status == 'pending' &&
          dueDate.isBefore(DateTime.now().copyWith(
            hour: 0,
            minute: 0,
            second: 0,
            millisecond: 0,
            microsecond: 0,
          )));

  /// Points this chore is worth based on its effort level.
  int get pointValue => effortPoints[effortLevel] ?? 10;

  /// Semantic color for the chore's current status.
  Color get statusColor {
    switch (status) {
      case 'complete':
        return const Color(0xFF4CAF50); // green
      case 'overdue':
        return const Color(0xFFD32F2F); // red
      case 'cancelled':
        return const Color(0xFF9E9E9E); // grey
      case 'pending':
      default:
        return const Color(0xFF2196F3); // blue
    }
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  factory ChoreModel.fromJson(Map<String, dynamic> json) {
    return ChoreModel(
      id: json['id'] as String,
      definitionId: json['definition_id'] as String,
      householdId: json['household_id'] as String,
      assigneeId: json['assignee_id'] as String?,
      assigneeName: json['assignee_name'] as String?,
      assignedManually: json['assigned_manually'] as bool,
      dueDate: DateTime.parse(json['due_date'] as String),
      status: json['status'] as String,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      pointsAwarded: json['points_awarded'] as int?,
      title: json['title'] as String,
      description: json['description'] as String?,
      category: json['category'] as String,
      effortLevel: json['effort_level'] as String,
      choreType: json['chore_type'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'definition_id': definitionId,
      'household_id': householdId,
      'assignee_id': assigneeId,
      'assignee_name': assigneeName,
      'assigned_manually': assignedManually,
      'due_date': dueDate.toIso8601String(),
      'status': status,
      'completed_at': completedAt?.toIso8601String(),
      'points_awarded': pointsAwarded,
      'title': title,
      'description': description,
      'category': category,
      'effort_level': effortLevel,
      'chore_type': choreType,
    };
  }
}
