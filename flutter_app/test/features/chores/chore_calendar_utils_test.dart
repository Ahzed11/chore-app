import 'package:chore_app/features/chores/models/chore_model.dart';
import 'package:chore_app/features/chores/utils/chore_calendar_utils.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

ChoreModel _chore({
  String id = 'c1',
  String status = 'pending',
  DateTime? dueDate,
  DateTime? completedAt,
}) {
  return ChoreModel(
    id: id,
    definitionId: 'def-$id',
    householdId: 'hh-1',
    assigneeId: 'user-1',
    assigneeName: 'Test User',
    assignedManually: false,
    createdAt: DateTime(2026, 1, 1),
    dueDate: dueDate ?? DateTime(2026, 8, 20),
    status: status,
    completedAt: completedAt,
    pointsAwarded: status == 'complete' ? 5 : null,
    title: 'Chore $id',
    description: null,
    category: 'kitchen',
    effortLevel: 'easy',
    choreType: 'recurring',
  );
}

void main() {
  group('calendarDateFor', () {
    test('complete maps to its completion date', () {
      final chore = _chore(
        status: 'complete',
        dueDate: DateTime(2026, 8, 10),
        completedAt: DateTime(2026, 8, 20, 14, 5),
      );
      expect(calendarDateFor(chore), DateTime(2026, 8, 20));
    });

    test('dismissed maps to its completion date', () {
      final chore = _chore(
        status: 'dismissed',
        dueDate: DateTime(2026, 8, 10),
        completedAt: DateTime(2026, 8, 21, 9, 30),
      );
      expect(calendarDateFor(chore), DateTime(2026, 8, 21));
    });

    test('pending maps to its due date', () {
      final chore = _chore(status: 'pending', dueDate: DateTime(2026, 9, 3));
      expect(calendarDateFor(chore), DateTime(2026, 9, 3));
    });

    test('overdue maps to its due date', () {
      final chore = _chore(status: 'overdue', dueDate: DateTime(2026, 7, 30));
      expect(calendarDateFor(chore), DateTime(2026, 7, 30));
    });

    test('cancelled is never placed on the calendar', () {
      final chore = _chore(
        status: 'cancelled',
        dueDate: DateTime(2026, 8, 20),
        completedAt: DateTime(2026, 8, 19),
      );
      expect(calendarDateFor(chore), isNull);
    });

    test('complete with a null completedAt is dropped', () {
      final chore = _chore(status: 'complete', dueDate: DateTime(2026, 8, 10));
      expect(calendarDateFor(chore), isNull);
    });

    test('the returned date is date-only (time stripped)', () {
      final pending = _chore(
        status: 'pending',
        dueDate: DateTime(2026, 8, 20, 23, 59, 59),
      );
      expect(calendarDateFor(pending), DateTime(2026, 8, 20));
      expect(calendarDateFor(pending)!.hour, 0);
      expect(calendarDateFor(pending)!.minute, 0);
    });

    test('a UTC completedAt is converted to its LOCAL day', () {
      // completed_at arrives from the server as UTC; the calendar day must be
      // the local one, otherwise a chore finished near midnight lands on the
      // wrong cell. 23:30 UTC is already "tomorrow" for positive offsets.
      final utc = DateTime.utc(2026, 8, 20, 23, 30);
      final local = utc.toLocal();
      final result = calendarDateFor(
        _chore(status: 'complete', completedAt: utc),
      );
      expect(result, DateTime(local.year, local.month, local.day));

      // When the machine's zone actually shifts the instant across a day
      // boundary, the UTC day must NOT be used (this is the regression the
      // `.toLocal()` call prevents). TZ-independent: on a UTC machine the
      // branches coincide and this is simply skipped.
      if (local.day != utc.day) {
        expect(result, isNot(DateTime(utc.year, utc.month, utc.day)));
      }
    });

    test('a UTC completedAt just after midnight local keeps the local day', () {
      final utc = DateTime.utc(2026, 8, 20, 0, 15);
      final local = utc.toLocal();
      final result = calendarDateFor(
        _chore(status: 'complete', completedAt: utc),
      );
      expect(result, DateTime(local.year, local.month, local.day));
    });
  });

  group('groupChoresByDay', () {
    test('groups chores by their calendar day', () {
      final chores = [
        _chore(id: 'a', status: 'pending', dueDate: DateTime(2026, 8, 20)),
        _chore(id: 'b', status: 'overdue', dueDate: DateTime(2026, 8, 21)),
        _chore(id: 'c', status: 'pending', dueDate: DateTime(2026, 8, 20)),
      ];

      final grouped = groupChoresByDay(chores);

      expect(grouped.keys.toSet(), {
        DateTime(2026, 8, 20),
        DateTime(2026, 8, 21),
      });
      expect(grouped[DateTime(2026, 8, 20)]!.map((c) => c.id), ['a', 'c']);
      expect(grouped[DateTime(2026, 8, 21)]!.single.id, 'b');
    });

    test('drops cancelled chores and chores with no placeable date', () {
      final chores = [
        _chore(id: 'a', status: 'pending', dueDate: DateTime(2026, 8, 20)),
        _chore(id: 'b', status: 'cancelled', dueDate: DateTime(2026, 8, 20)),
        // complete without completedAt → unplaceable
        _chore(id: 'c', status: 'complete', dueDate: DateTime(2026, 8, 20)),
      ];

      final grouped = groupChoresByDay(chores);

      expect(grouped.keys, [DateTime(2026, 8, 20)]);
      expect(grouped[DateTime(2026, 8, 20)]!.map((c) => c.id), ['a']);
    });

    test('a done chore and a due chore on the same day share a bucket', () {
      final chores = [
        _chore(id: 'done', status: 'complete', completedAt: DateTime(2026, 8, 20)),
        _chore(id: 'due', status: 'pending', dueDate: DateTime(2026, 8, 20)),
      ];

      final grouped = groupChoresByDay(chores);

      expect(grouped.keys, [DateTime(2026, 8, 20)]);
      expect(grouped[DateTime(2026, 8, 20)]!.map((c) => c.id), ['done', 'due']);
    });

    test('an empty list groups to an empty map', () {
      expect(groupChoresByDay(const []), isEmpty);
    });

    test('all-cancelled input groups to an empty map', () {
      final chores = [
        _chore(id: 'a', status: 'cancelled'),
        _chore(id: 'b', status: 'cancelled'),
      ];
      expect(groupChoresByDay(chores), isEmpty);
    });
  });
}
