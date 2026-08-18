import 'dart:async';

import 'package:chore_app/features/chores/models/chore_form_init_data.dart';
import 'package:chore_app/features/chores/models/chore_model.dart';
import 'package:chore_app/features/chores/models/chore_template.dart';
import 'package:chore_app/features/chores/providers/chore_templates_provider.dart';
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

/// Resolves instantly and never hits a real Dio — used by submit-success
/// tests (TASK-060) so `await notifier.updateChoreDefinition(...)` in
/// `_submit()` completes within a single `pump()` instead of falling through
/// to the real, unmocked `dioProvider`.
class _InstantChoresNotifier extends ChoresNotifier {
  final List<({String definitionId, Map<String, dynamic> body})> updateCalls =
      [];

  @override
  Future<List<ChoreModel>> build(String arg) async => const [];

  @override
  Future<void> updateChoreDefinition(
    String definitionId,
    Map<String, dynamic> body,
  ) async {
    updateCalls.add((definitionId: definitionId, body: body));
  }
}

class _FakeChoreTemplatesNotifier extends ChoreTemplatesNotifier {
  _FakeChoreTemplatesNotifier(this._templates);
  final List<ChoreTemplate> _templates;

  @override
  Future<List<ChoreTemplate>> build(String arg) async => _templates;

  @override
  Future<void> hideTemplate(String definitionId) async {}
}

/// Templates provider whose build throws — drives the
/// `friendlyErrorMessage` snackbar path in `_pickTemplateToCopy`
/// (required by TASK-109's test list; previously untested).
class _ThrowingTemplatesNotifier extends ChoreTemplatesNotifier {
  @override
  Future<List<ChoreTemplate>> build(String arg) async =>
      throw Exception('boom');
}

ChoreTemplate _template({
  String id = 't1',
  String title = 'Vacuum',
  String? description = 'Deep clean',
  String category = 'living_room',
  String effortLevel = 'hard',
}) {
  return ChoreTemplate(
    id: id,
    title: title,
    description: description,
    category: category,
    effortLevel: effortLevel,
  );
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
  List<ChoreTemplate> templates = const [],
  ChoreTemplatesNotifier Function()? templatesFactory,
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
      choreTemplatesProvider.overrideWith(
        templatesFactory ?? () => _FakeChoreTemplatesNotifier(templates),
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
          'does NOT show "Due date cannot be in the past" when initData '
          'carries an unchanged past date (TASK-060)',
          (tester) async {
        // The date picker enforces firstDate=today, but a chore in edit mode
        // might carry a past date (e.g. it slipped, or the clock just ticked
        // over) — the admin must still be able to save it back unchanged
        // instead of being trapped in a validation error with no way to
        // clear it (the picker itself can't select a past date to "fix" it
        // to). See `_dueDateManuallyChanged` in create_chore_screen.dart.
        _expandView(tester);

        final pastData = ChoreFormInitData(
          definitionId: 'def-past',
          title: 'Old chore',
          category: 'kitchen',
          effortLevel: 'easy',
          choreType: 'one_off',
          firstDueDate: DateTime(2020, 6, 1), // clearly in the past
        );

        final notifier = _InstantChoresNotifier();
        await tester.pumpWidget(
          _buildScreen(initData: pastData, choresFactory: () => notifier),
        );
        await tester.pump();

        // Title and category are pre-filled from initData; submit directly
        // without touching the due-date field.
        await tester.tap(find.byKey(const Key('submit_button')));
        await tester.pump();

        expect(find.text('Due date cannot be in the past'), findsNothing);
        expect(notifier.updateCalls, hasLength(1));
        expect(notifier.updateCalls.single.body['first_due_date'], '2020-06-01');
      });

      testWidgets(
          'create mode (no initData) still rejects a past due date '
          '(TASK-060 only relaxes edit mode)',
          (tester) async {
        // Sanity check for the other half of the branch: create mode has no
        // `_dueDateManuallyChanged` exemption at all, so nothing here should
        // have changed for it. There's no UI path to a past date in create
        // mode (the picker enforces firstDate=today), so this only proves
        // the validator's `_isEditMode` gate is doing its job — a missing
        // date still trips its own, separate message.
        _expandView(tester);
        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        await tester.tap(find.byKey(const Key('submit_button')));
        await tester.pump();

        expect(find.text('Please select a due date'), findsOneWidget);
        expect(find.text('Due date cannot be in the past'), findsNothing);
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

    // =========================================================================
    // Copy from existing task (TASK-108)
    // =========================================================================

    group('copy from existing task (TASK-108)', () {
      testWidgets('button present in create mode, absent in edit mode',
          (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('copy_from_task_button')), findsOneWidget);

        // Edit mode: no copy control.
        final editData = ChoreFormInitData(
          definitionId: 'def-42',
          title: 'Existing chore',
          category: 'bedroom',
          effortLevel: 'hard',
          choreType: 'one_off',
          firstDueDate: DateTime.now().add(const Duration(days: 14)),
        );
        await tester.pumpWidget(_buildScreen(initData: editData));
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('copy_from_task_button')), findsNothing);
      });

      testWidgets('no existing tasks → snackbar, no sheet', (tester) async {
        _expandView(tester);
        await tester.pumpWidget(_buildScreen()); // templates: const [] default
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byKey(const Key('copy_from_task_button')));
        await tester.pump();

        expect(find.text('No existing tasks to copy yet.'), findsOneWidget);
        expect(find.byKey(const Key('copy_task_t1')), findsNothing);
      });

      testWidgets(
          'selecting a task copies title, description, category and effort '
          'level', (tester) async {
        _expandView(tester);
        final templates = [
          _template(
            id: 't1',
            title: 'Vacuum living room',
            description: 'Including under the sofa',
            category: 'living_room',
            effortLevel: 'hard',
          ),
        ];

        await tester.pumpWidget(_buildScreen(templates: templates));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byKey(const Key('copy_from_task_button')));
        await tester.pumpAndSettle();

        // The sheet lists the task.
        expect(find.byKey(const Key('copy_task_t1')), findsOneWidget);
        expect(find.text('Vacuum living room'), findsWidgets);

        // Select it.
        await tester.tap(find.byKey(const Key('copy_task_t1')));
        await tester.pumpAndSettle();

        // Title + description copied into the fields.
        expect(
          find.descendant(
            of: find.byKey(const Key('title_field')),
            matching: find.text('Vacuum living room'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('description_field')),
            matching: find.text('Including under the sofa'),
          ),
          findsOneWidget,
        );
        // Category dropdown shows the copied category label.
        expect(find.text('Living Room'), findsWidgets);
        // Effort selector has 'hard' selected.
        final selector = tester.widget<SegmentedButton<String>>(
          find.descendant(
            of: find.byKey(const Key('effort_level_selector')),
            matching: find.byType(SegmentedButton<String>),
          ),
        );
        expect(selector.selected, contains('hard'));
      });

      testWidgets(
          'with 15 templates: scrolls to the LAST row, taps it, and the '
          '4 fields are copied (TASK-109)', (tester) async {
        // Phone-ish viewport (400x800): the sheet opens at 50% height, which
        // cannot fit 15 rows — scrolling to the last row is genuinely
        // required, and the old Flexible+shrinkWrap sheet would have filled
        // the whole screen here instead.
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final templates = [
          for (var i = 1; i <= 15; i++)
            _template(
              id: 't$i',
              title: 'Template task $i',
              description: 'Description $i',
              category: i.isEven ? 'living_room' : 'kitchen',
              effortLevel: i.isEven ? 'hard' : 'easy',
            ),
        ];
        await tester.pumpWidget(_buildScreen(templates: templates));
        await tester.pump();
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const Key('copy_from_task_button')),
        );
        await tester.tap(find.byKey(const Key('copy_from_task_button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // The sheet is a draggable half-height panel, NOT full-screen (the
        // old sheet expanded to full height with many templates).
        final sheetHeight =
            tester.getSize(find.byType(BottomSheet)).height;
        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        expect(sheetHeight, lessThan(screenHeight));

        // The last row starts below the fold — scrolling is required.
        expect(find.byKey(const Key('copy_task_t15')), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const Key('copy_task_t15')),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(tester.takeException(), isNull);

        // Tap the last row and assert all 4 fields copied.
        await tester.tap(find.byKey(const Key('copy_task_t15')));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('title_field')),
            matching: find.text('Template task 15'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('description_field')),
            matching: find.text('Description 15'),
          ),
          findsOneWidget,
        );
        // Template 15 is odd → kitchen + easy.
        expect(find.text('Kitchen'), findsWidgets);
        final selector = tester.widget<SegmentedButton<String>>(
          find.descendant(
            of: find.byKey(const Key('effort_level_selector')),
            matching: find.byType(SegmentedButton<String>),
          ),
        );
        expect(selector.selected, contains('easy'));
      });

      testWidgets('templates provider error → friendlyErrorMessage snackbar',
          (tester) async {
        _expandView(tester);
        await tester.pumpWidget(
          _buildScreen(
            templatesFactory: () => _ThrowingTemplatesNotifier(),
          ),
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byKey(const Key('copy_from_task_button')));
        await tester.pumpAndSettle();

        // Non-DioException errors map to the generic friendly message
        // (friendly_error.dart); the raw exception must never leak.
        expect(
          find.text('Something went wrong. Please try again.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('copy_task_t1')), findsNothing);
      });
    });
  });
}
