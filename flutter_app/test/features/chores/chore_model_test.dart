import 'package:chore_app/features/chores/models/chore_model.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChoreModel dismissed status (TASK-103)', () {
    test('fromJson/toJson round-trips a dismissed chore with no points', () {
      final json = <String, dynamic>{
        'id': 'inst-1',
        'definition_id': 'def-1',
        'household_id': 'hh-1',
        'assignee_id': 'user-1',
        'assignee_name': 'Alice',
        'assigned_manually': false,
        'created_at': '2027-01-01T00:00:00Z',
        'due_date': '2027-01-01T00:00:00Z',
        'status': 'dismissed',
        'completed_at': '2027-01-02T00:00:00Z',
        'points_awarded': null,
        'title': 'Take out trash',
        'description': null,
        'category': 'kitchen',
        'effort_level': 'easy',
        'chore_type': 'one_off',
      };

      final model = ChoreModel.fromJson(json);

      expect(model.status, 'dismissed');
      expect(model.pointsAwarded, isNull);
      expect(model.completedAt, isNotNull);

      // A dismissed chore must never read as overdue, and must not present
      // as worth points anywhere the model derives values.
      expect(model.isOverdue, isFalse);
      expect(model.statusColor, const Color(0xFF9E9E9E));

      final roundTripped = ChoreModel.fromJson(model.toJson());
      expect(roundTripped.status, 'dismissed');
      expect(roundTripped.pointsAwarded, isNull);
      expect(roundTripped.completedAt, model.completedAt);
      expect(roundTripped.assigneeName, 'Alice');
    });
  });
}
