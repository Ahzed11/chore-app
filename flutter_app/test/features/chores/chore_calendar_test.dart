import 'package:chore_app/core/config/app_locale.dart';
import 'package:chore_app/features/chores/models/chore_model.dart';
import 'package:chore_app/features/chores/widgets/chore_calendar.dart';
import 'package:chore_app/features/chores/widgets/chore_card.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

ChoreModel _chore({
  String id = 'c1',
  String title = 'Wash dishes',
  String status = 'pending',
  String category = 'kitchen',
  String effortLevel = 'easy',
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
    title: title,
    description: null,
    category: category,
    effortLevel: effortLevel,
    choreType: 'recurring',
  );
}

/// The calendar renders inside the app's real locale config (en_GB, Monday
/// first) — mirrored here so the widget test cannot drift from production.
Widget _app(List<ChoreModel> chores) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    locale: kAppLocale,
    supportedLocales: kSupportedLocales,
    localizationsDelegates: kLocalizationsDelegates,
    home: Scaffold(body: ChoreCalendar(chores: chores)),
  );
}

Key _dayKey(DateTime day) =>
    Key('calendar_day_${day.year}_${day.month}_${day.day}');

/// The 5×5 status-dot containers inside a day cell.
final Finder _markerDots = find.byWidgetPredicate(
  (Widget w) =>
      w is Container &&
      w.constraints?.maxWidth == 5 &&
      w.constraints?.maxHeight == 5,
);

Finder _dotsOn(DateTime day) =>
    find.descendant(of: find.byKey(_dayKey(day)), matching: _markerDots);

Color? _firstDotColor(WidgetTester tester, DateTime day) {
  final dot = tester.widget<Container>(_dotsOn(day).first);
  return (dot.decoration as BoxDecoration?)?.color;
}

/// A day inside the CURRENT month that is not [except] (so "empty day" is
/// never accidentally the day holding the fixture chore).
DateTime _otherDayInMonth(DateTime except) =>
    except.day == 1
        ? DateTime(except.year, except.month, 2)
        : DateTime(except.year, except.month, 1);

void main() {
  group('ChoreCalendar', () {
    final today = DateTime.now();

    testWidgets('renders a Monday-first weekday header (Mon…Sun)',
        (tester) async {
      await tester.pumpWidget(_app([]));
      await tester.pumpAndSettle();

      for (final label in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        expect(find.text(label), findsOneWidget);
      }
      // Monday is leftmost — the grid is Monday-first, not Sunday-first.
      expect(
        tester.getTopLeft(find.text('Mon')).dx,
        lessThan(tester.getTopLeft(find.text('Sun')).dx),
      );
    });

    testWidgets('shows the current month in the header', (tester) async {
      await tester.pumpWidget(_app([]));
      await tester.pumpAndSettle();

      expect(find.text(DateFormat('MMMM yyyy').format(today)), findsOneWidget);
    });

    testWidgets('a completed chore is marked on its completion day only',
        (tester) async {
      final done = _chore(
        id: 'done',
        title: 'Wash the car',
        status: 'complete',
        completedAt: DateTime(today.year, today.month, today.day, 10, 30),
      );
      final emptyDay = _otherDayInMonth(today);

      await tester.pumpWidget(_app([done]));
      await tester.pumpAndSettle();

      expect(_dotsOn(today), findsOneWidget);
      expect(_firstDotColor(tester, today), done.statusColor);
      // A day without chores shows nothing.
      expect(_dotsOn(emptyDay), findsNothing);
    });

    testWidgets('a pending chore is marked on its due day', (tester) async {
      final due = _chore(
        id: 'due',
        status: 'pending',
        dueDate: DateTime(today.year, today.month, today.day, 8),
      );

      await tester.pumpWidget(_app([due]));
      await tester.pumpAndSettle();

      expect(_dotsOn(today), findsOneWidget);
      expect(_firstDotColor(tester, today), due.statusColor);
    });

    testWidgets('a cancelled chore renders no marker at all', (tester) async {
      final cancelled = _chore(
        id: 'cancelled',
        status: 'cancelled',
        dueDate: DateTime(today.year, today.month, today.day),
      );

      await tester.pumpWidget(_app([cancelled]));
      await tester.pumpAndSettle();

      expect(_dotsOn(today), findsNothing);
    });

    testWidgets('shows at most 3 dots and an overflow count', (tester) async {
      final chores = [
        for (var i = 0; i < 5; i++)
          _chore(
            id: 'c$i',
            status: 'pending',
            dueDate: DateTime(today.year, today.month, today.day),
          ),
      ];

      await tester.pumpWidget(_app(chores));
      await tester.pumpAndSettle();

      expect(_dotsOn(today), findsNWidgets(3));
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('tapping a day with chores opens the day sheet, read-only',
        (tester) async {
      final done = _chore(
        id: 'done',
        title: 'Wash the car',
        status: 'complete',
        completedAt: DateTime(today.year, today.month, today.day, 10),
      );

      await tester.pumpWidget(_app([done]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_dayKey(today)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('calendar_day_sheet_title')), findsOneWidget);
      expect(find.text('Wash the car'), findsOneWidget);
      expect(find.text('1 chore'), findsOneWidget);

      // Read-only: the sheet's cards carry no mutation callbacks.
      expect(find.byType(ChoreCard), findsOneWidget);
      final card = tester.widget<ChoreCard>(find.byType(ChoreCard));
      expect(card.onCompleteTap, isNull);
      expect(card.onDismiss, isNull);
      expect(card.onDeleteSeries, isNull);
      expect(card.onReassign, isNull);
      expect(card.onMarkDoneForAssignee, isNull);
    });

    testWidgets('tapping an empty day shows the empty-day message',
        (tester) async {
      final done = _chore(
        id: 'done',
        status: 'complete',
        completedAt: DateTime(today.year, today.month, today.day, 10),
      );
      final emptyDay = _otherDayInMonth(today);

      await tester.pumpWidget(_app([done]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_dayKey(emptyDay)));
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing done or due on this day.'),
        findsOneWidget,
      );
      expect(find.text('No chores on this date.'), findsOneWidget);
      expect(find.byType(ChoreCard), findsNothing);
    });

    testWidgets('prev / next / Today change the displayed month',
        (tester) async {
      final prev = DateTime(today.year, today.month - 1);
      final next = DateTime(today.year, today.month + 1);
      String label(DateTime m) => DateFormat('MMMM yyyy').format(m);

      await tester.pumpWidget(_app([]));
      await tester.pumpAndSettle();
      expect(find.text(label(today)), findsOneWidget);

      await tester.tap(find.byKey(const Key('calendar_prev_month')));
      await tester.pumpAndSettle();
      expect(find.text(label(prev)), findsOneWidget);

      await tester.tap(find.byKey(const Key('calendar_next_month')));
      await tester.pumpAndSettle();
      expect(find.text(label(today)), findsOneWidget);

      await tester.tap(find.byKey(const Key('calendar_next_month')));
      await tester.pumpAndSettle();
      expect(find.text(label(next)), findsOneWidget);

      await tester.tap(find.byKey(const Key('calendar_today')));
      await tester.pumpAndSettle();
      expect(find.text(label(today)), findsOneWidget);
    });

    testWidgets('day cells expose an accessible date + chore-count label',
        (tester) async {
      // Must be disposed before the test body ends (flutter_test verifies no
      // SemanticsHandle is left active), so no addTearDown here.
      final handle = tester.ensureSemantics();

      final done = _chore(
        id: 'done',
        status: 'complete',
        completedAt: DateTime(today.year, today.month, today.day, 10),
      );
      final pending = _chore(
        id: 'due',
        status: 'pending',
        dueDate: DateTime(today.year, today.month, today.day),
      );
      final emptyDay = _otherDayInMonth(today);

      await tester.pumpWidget(_app([done, pending]));
      await tester.pumpAndSettle();

      // TalkBack/VoiceOver must announce the full date and the day's load —
      // the visible content is only a bare number plus dots.
      expect(
        find.bySemanticsLabel(
          RegExp('^${DateFormat('EEEE, d MMMM').format(today)}, 2 chores\$'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('^${DateFormat('EEEE, d MMMM').format(emptyDay)}, '
              'no chores\$'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('month navigation re-places chores on the grid',
        (tester) async {
      // Due next month → no marker this month, marker after one "next" tap.
      const nextMonthDay = 15;
      final nextMonth = DateTime(today.year, today.month + 1, nextMonthDay);
      final due = _chore(id: 'due', status: 'pending', dueDate: nextMonth);

      await tester.pumpWidget(_app([due]));
      await tester.pumpAndSettle();
      expect(_dotsOn(nextMonth), findsNothing);

      await tester.tap(find.byKey(const Key('calendar_next_month')));
      await tester.pumpAndSettle();

      expect(find.text(DateFormat('MMMM yyyy').format(nextMonth)),
          findsOneWidget);
      expect(_dotsOn(nextMonth), findsOneWidget);
      expect(_firstDotColor(tester, nextMonth), due.statusColor);
    });
  });
}
