import 'dart:async';

import 'package:chore_app/features/chores/models/chore_form_init_data.dart';
import 'package:chore_app/features/chores/models/chore_model.dart';
import 'package:chore_app/features/chores/providers/chores_provider.dart';
import 'package:chore_app/features/chores/screens/create_chore_screen.dart';
import 'package:chore_app/features/household/models/household_model.dart';
import 'package:chore_app/features/household/models/member_model.dart';
import 'package:chore_app/features/household/providers/household_provider.dart';
import 'package:chore_app/features/household/providers/members_provider.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

const _kHouseholdId = 'hh-1';

MemberModel _member({String id = 'user-1', String name = 'Alice'}) =>
    MemberModel(
      userId: id,
      displayName: name,
      role: 'member',
      joinedAt: DateTime(2025, 6, 1),
    );

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

class _FakeHouseholdsNotifier extends HouseholdsNotifier {
  _FakeHouseholdsNotifier({required this.isAdmin});
  final bool isAdmin;

  @override
  Future<List<HouseholdModel>> build() async => [
        HouseholdModel(
          id: _kHouseholdId,
          name: 'Test Home',
          role: isAdmin ? 'admin' : 'member',
          memberCount: 2,
          createdAt: DateTime(2025, 1, 1),
        ),
      ];
}

class _FakeMembersNotifier extends MembersNotifier {
  _FakeMembersNotifier(this._members);
  final List<MemberModel> _members;

  @override
  Future<List<MemberModel>> build(String arg) async => _members;
}

class _LoadingChoresNotifier extends ChoresNotifier {
  @override
  Future<List<ChoreModel>> build(String arg) =>
      Completer<List<ChoreModel>>().future;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Expands the test viewport so the entire form fits without scrolling.
/// Without this, elements below ~600px cannot receive tap events.
void _expandView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _buildScreen({
  ChoreFormInitData? initData,
  bool isAdmin = true,
  List<MemberModel> members = const [],
  ChoresNotifier Function()? choresFactory,
}) {
  return ProviderScope(
    overrides: [
      householdsNotifierProvider.overrideWith(
        () => _FakeHouseholdsNotifier(isAdmin: isAdmin),
      ),
      membersNotifierProvider.overrideWith(
        () => _FakeMembersNotifier(members),
      ),
      choresNotifierProvider.overrideWith(
        choresFactory ?? _LoadingChoresNotifier.new,
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateChoreScreen(
        householdId: _kHouseholdId,
        initData: initData,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CreateChoreScreen', () {
    // =========================================================================
    // Task requirement 1: Recurrence fields shown only when Recurring selected
    // =========================================================================

    group('recurrence fields', () {
      testWidgets('are hidden when "One-off" is selected (default)',
          (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.byKey(const Key('recurrence_section')), findsNothing);
        expect(find.byKey(const Key('interval_n_field')), findsNothing);
        expect(find.byKey(const Key('interval_unit_dropdown')), findsNothing);
      });

      testWidgets('are shown when "Recurring" radio is tapped', (tester) async {
        _expandView(tester);
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        await tester.tap(find.byKey(const Key('type_recurring')));
        await tester.pump();

        expect(find.byKey(const Key('recurrence_section')), findsOneWidget);
        expect(find.byKey(const Key('interval_n_field')), findsOneWidget);
        expect(find.byKey(const Key('interval_unit_dropdown')), findsOneWidget);
      });

      testWidgets('disappear when switching back to "One-off"', (tester) async {
        _expandView(tester);
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        await tester.tap(find.byKey(const Key('type_recurring')));
        await tester.pump();
        expect(find.byKey(const Key('recurrence_section')), findsOneWidget);

        await tester.tap(find.byKey(const Key('type_one_off')));
        await tester.pump();
        expect(find.byKey(const Key('recurrence_section')), findsNothing);
      });

      testWidgets(
          'interval unit dropdown contains Days, Weeks, Months when opened',
          (tester) async {
        _expandView(tester);
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        // Switch to recurring to reveal the recurrence section.
        await tester.tap(find.byKey(const Key('type_recurring')));
        await tester.pump();

        // Tap the unit dropdown to open it.
        await tester.tap(find.byKey(const Key('interval_unit_dropdown')));
        await tester.pumpAndSettle();

        // Each option appears at least once (selected item + menu item).
        expect(find.text('Days'), findsWidgets);
        expect(find.text('Weeks'), findsWidgets);
        expect(find.text('Months'), findsWidgets);
      });
    });

    // =========================================================================
    // Task requirement 2: Form validation blocks submission with empty title
    // =========================================================================

    group('form validation', () {
      testWidgets('shows "Title is required" when title is empty on submit',
          (tester) async {
        _expandView(tester);
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        // Leave title empty; tap submit.
        await tester.tap(find.byKey(const Key('submit_button')));
        await tester.pump();

        expect(find.text('Title is required'), findsOneWidget);
      });

      testWidgets(
          'shows "Please select a category" when category is missing on submit',
          (tester) async {
        _expandView(tester);
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        await tester.enterText(
            find.byKey(const Key('title_field')), 'Clean kitchen');
        await tester.tap(find.byKey(const Key('submit_button')));
        await tester.pump();

        expect(find.text('Please select a category'), findsOneWidget);
      });

      testWidgets('shows "Please select a due date" when date is missing',
          (tester) async {
        _expandView(tester);
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        await tester.enterText(
            find.byKey(const Key('title_field')), 'Mop floors');
        // Leave date empty; tap submit.
        await tester.tap(find.byKey(const Key('submit_button')));
        await tester.pump();

        expect(find.text('Please select a due date'), findsOneWidget);
      });

      testWidgets(
          'shows recurrence interval error when interval field is empty',
          (tester) async {
        _expandView(tester);
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        await tester.tap(find.byKey(const Key('type_recurring')));
        await tester.pump();

        // Clear the default value from the interval N field.
        await tester.enterText(
            find.byKey(const Key('interval_n_field')), '');
        await tester.tap(find.byKey(const Key('submit_button')));
        await tester.pump();

        expect(find.text('Required'), findsOneWidget);
      });

      testWidgets('shows interval error when interval value is zero',
          (tester) async {
        _expandView(tester);
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        await tester.tap(find.byKey(const Key('type_recurring')));
        await tester.pump();

        await tester.enterText(
            find.byKey(const Key('interval_n_field')), '0');
        await tester.tap(find.byKey(const Key('submit_button')));
        await tester.pump();

        expect(find.text('Min 1'), findsOneWidget);
      });
    });

    // =========================================================================
    // Task requirement 3: Effort level shows correct point values
    // =========================================================================

    group('effort level selector', () {
      testWidgets('displays Easy with 10 pts, Medium with 25 pts, Hard with 50 pts',
          (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.text('Easy'), findsOneWidget);
        expect(find.text('10 pts'), findsOneWidget);

        expect(find.text('Medium'), findsOneWidget);
        expect(find.text('25 pts'), findsOneWidget);

        expect(find.text('Hard'), findsOneWidget);
        expect(find.text('50 pts'), findsOneWidget);
      });

      testWidgets('selector widget is present in the form', (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.byKey(const Key('effort_level_selector')), findsOneWidget);
      });
    });

    // =========================================================================
    // Task requirement 4: Date validation catches past dates
    // =========================================================================

    group('due date validation', () {
      testWidgets(
          'shows "Due date cannot be in the past" when initData carries a past date',
          (tester) async {
        // The date picker enforces firstDate=today, but a chore in edit mode
        // might carry a past date (e.g. clock change, existing stale record).
        // This verifies the validator catches it on submit.
        _expandView(tester);

        final pastData = ChoreFormInitData(
          definitionId: 'def-past',
          title: 'Old chore',
          category: 'kitchen',
          effortLevel: 'easy',
          choreType: 'one_off',
          firstDueDate: DateTime(2020, 6, 1), // clearly in the past
        );

        await tester.pumpWidget(_buildScreen(initData: pastData));
        await tester.pump();

        // Title and category are pre-filled from initData; submit directly.
        await tester.tap(find.byKey(const Key('submit_button')));
        await tester.pump();

        expect(find.text('Due date cannot be in the past'), findsOneWidget);
      });

      testWidgets('shows date trigger field', (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.byKey(const Key('due_date_field')), findsOneWidget);
      });

      testWidgets('pre-populated date is displayed in the field when editing',
          (tester) async {
        final futureDate = DateTime(2027, 8, 15);
        final initData = ChoreFormInitData(
          definitionId: 'def-99',
          title: 'Future chore',
          category: 'kitchen',
          effortLevel: 'medium',
          choreType: 'one_off',
          firstDueDate: futureDate,
        );

        await tester.pumpWidget(_buildScreen(initData: initData));
        await tester.pump();

        // The date field controller formats as 'EEE, d MMM yyyy'.
        expect(find.text('Sun, 15 Aug 2027'), findsOneWidget);
      });
    });

    // =========================================================================
    // Create mode appearance
    // =========================================================================

    group('create mode', () {
      testWidgets('shows "Create Chore" in the app bar', (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        // The AppBar title says "Create Chore". The submit button also shows
        // "Create Chore", so we narrow the search to the AppBar.
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Create Chore'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('does NOT show the edit-mode banner', (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.byKey(const Key('edit_mode_banner')), findsNothing);
        expect(
            find.text('Changes apply to future instances only.'), findsNothing);
      });

      testWidgets('submit button label is "Create Chore"', (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        final button = tester.widget<ElevatedButton>(
          find.byKey(const Key('submit_button')),
        );
        expect((button.child as Text?)?.data, 'Create Chore');
      });
    });

    // =========================================================================
    // Edit mode appearance
    // =========================================================================

    group('edit mode', () {
      ChoreFormInitData editData() => ChoreFormInitData(
            definitionId: 'def-42',
            title: 'Existing chore',
            description: 'Some notes',
            category: 'bedroom',
            effortLevel: 'hard',
            choreType: 'recurring',
            firstDueDate: DateTime.now().add(const Duration(days: 14)),
            intervalUnit: 'weeks',
            intervalN: 2,
          );

      testWidgets('shows "Edit Chore" in the app bar', (tester) async {
        await tester.pumpWidget(_buildScreen(initData: editData()));
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Edit Chore'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('shows the edit-mode banner with correct message',
          (tester) async {
        await tester.pumpWidget(_buildScreen(initData: editData()));
        await tester.pump();

        expect(find.byKey(const Key('edit_mode_banner')), findsOneWidget);
        expect(
          find.text('Changes apply to future instances only.'),
          findsOneWidget,
        );
      });

      testWidgets('pre-populates the title field', (tester) async {
        await tester.pumpWidget(_buildScreen(initData: editData()));
        await tester.pump();

        expect(find.text('Existing chore'), findsOneWidget);
      });

      testWidgets('shows recurrence section when choreType is recurring',
          (tester) async {
        await tester.pumpWidget(_buildScreen(initData: editData()));
        await tester.pump();

        expect(find.byKey(const Key('recurrence_section')), findsOneWidget);
      });

      testWidgets('submit button label is "Save Changes"', (tester) async {
        await tester.pumpWidget(_buildScreen(initData: editData()));
        await tester.pump();

        final button = tester.widget<ElevatedButton>(
          find.byKey(const Key('submit_button')),
        );
        expect((button.child as Text?)?.data, 'Save Changes');
      });
    });

    // =========================================================================
    // Admin guard
    // =========================================================================

    group('admin guard', () {
      testWidgets('shows access-denied message for non-admin users',
          (tester) async {
        await tester.pumpWidget(_buildScreen(isAdmin: false));
        await tester.pump();

        expect(find.text('Admin access required'), findsOneWidget);
        expect(find.byKey(const Key('submit_button')), findsNothing);
      });

      testWidgets('shows the full form for admin users', (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.byKey(const Key('submit_button')), findsOneWidget);
        expect(find.text('Admin access required'), findsNothing);
      });
    });

    // =========================================================================
    // Assignee dropdown
    // =========================================================================

    group('assignee dropdown', () {
      testWidgets('shows member names and auto-assign option when loaded',
          (tester) async {
        _expandView(tester);
        final members = [
          _member(id: 'u1', name: 'Alice'),
          _member(id: 'u2', name: 'Bob'),
        ];

        await tester.pumpWidget(_buildScreen(members: members));
        // First pump resolves householdsNotifierProvider (admin check) and
        // triggers the Form render, which initialises membersNotifierProvider.
        await tester.pump();
        // Second pump resolves membersNotifierProvider so the dropdown builds.
        await tester.pump();

        // Open the assignee dropdown.
        await tester.tap(find.byKey(const Key('assignee_dropdown')));
        await tester.pumpAndSettle();

        expect(find.text('Alice'), findsWidgets);
        expect(find.text('Bob'), findsWidgets);
        expect(find.text('Auto-assign'), findsWidgets);
      });
    });

    // =========================================================================
    // Core form fields presence
    // =========================================================================

    group('form fields', () {
      testWidgets('all required fields are present in the widget tree',
          (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        // All fields are in the tree regardless of viewport via
        // SingleChildScrollView + Column (non-lazy layout).
        expect(find.byKey(const Key('title_field')), findsOneWidget);
        expect(find.byKey(const Key('description_field')), findsOneWidget);
        expect(find.byKey(const Key('category_dropdown')), findsOneWidget);
        expect(find.byKey(const Key('effort_level_selector')), findsOneWidget);
        expect(find.byKey(const Key('type_one_off')), findsOneWidget);
        expect(find.byKey(const Key('type_recurring')), findsOneWidget);
        expect(find.byKey(const Key('due_date_field')), findsOneWidget);
        expect(find.byKey(const Key('submit_button')), findsOneWidget);
      });
    });
  });
}
