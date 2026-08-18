import 'package:chore_app/features/auth/providers/current_user_provider.dart';
import 'package:chore_app/features/chores/models/chore_form_init_data.dart';
import 'package:chore_app/features/chores/models/chore_model.dart';
import 'package:chore_app/features/chores/providers/chores_provider.dart';
import 'package:chore_app/features/chores/screens/chore_list_screen.dart';
import 'package:chore_app/features/chores/screens/create_chore_screen.dart';
import 'package:chore_app/features/household/models/household_model.dart';
import 'package:chore_app/features/household/models/member_model.dart';
import 'package:chore_app/features/household/providers/household_provider.dart';
import 'package:chore_app/features/household/providers/members_provider.dart';
import 'package:chore_app/router/app_router.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Test constants & data helpers
// ---------------------------------------------------------------------------

const _kHouseholdId = 'hh-1';
const _kCurrentUserId = 'user-1';

ChoreModel _chore({
  String id = 'c1',
  String title = 'Wash dishes',
  String? description = 'Load and run the dishwasher',
  String status = 'pending',
  String category = 'kitchen',
  String effortLevel = 'easy',
  String choreType = 'one_off',
  String? assigneeId = 'user-2',
  String? assigneeName = 'Bob',
  DateTime? dueDate,
  DateTime? createdAt,
}) {
  return ChoreModel(
    id: id,
    definitionId: 'def-$id',
    householdId: _kHouseholdId,
    assigneeId: assigneeId,
    assigneeName: assigneeName,
    assignedManually: false,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    dueDate: dueDate ?? DateTime(2027, 6, 25),
    status: status,
    title: title,
    description: description,
    category: category,
    effortLevel: effortLevel,
    choreType: choreType,
  );
}

HouseholdModel _household({String role = 'admin'}) {
  return HouseholdModel(
    id: _kHouseholdId,
    name: 'Test Home',
    role: role,
    memberCount: 2,
    createdAt: DateTime(2025, 1, 1),
  );
}

MemberModel _member({
  String userId = 'user-2',
  String displayName = 'Bob',
  String role = 'member',
}) {
  return MemberModel(
    userId: userId,
    displayName: displayName,
    role: role,
    joinedAt: DateTime(2025, 3, 1),
  );
}

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

class _TrackingChoresNotifier extends ChoresNotifier {
  _TrackingChoresNotifier(this._chores);
  final List<ChoreModel> _chores;

  final List<({String definitionId, Map<String, dynamic> body})> updateCalls =
      [];

  @override
  Future<List<ChoreModel>> build(String arg) async => _chores;

  @override
  Future<void> updateChoreDefinition(
    String definitionId,
    Map<String, dynamic> body,
  ) async {
    updateCalls.add((definitionId: definitionId, body: body));
  }

  @override
  Future<void> refresh() async {}
}

class _FakeMembersNotifier extends MembersNotifier {
  _FakeMembersNotifier(this._members);
  final List<MemberModel> _members;

  @override
  Future<List<MemberModel>> build(String arg) async => _members;
}

class _DataHouseholdsNotifier extends HouseholdsNotifier {
  _DataHouseholdsNotifier(this._households);
  final List<HouseholdModel> _households;

  @override
  Future<List<HouseholdModel>> build() async => _households;
}

// ---------------------------------------------------------------------------
// Widget builder helper — a real GoRouter with both the chore-list and
// create/edit routes, since editing requires an actual navigation +
// `extra` handoff (unlike the callback-based reassign flow).
// ---------------------------------------------------------------------------

Widget _buildApp({
  required ChoresNotifier Function() choresNotifier,
  List<HouseholdModel>? households,
  List<MemberModel>? members,
}) {
  final router = GoRouter(
    initialLocation: '/households/$_kHouseholdId/chores',
    routes: [
      GoRoute(
        path: '/households/:householdId/chores',
        name: AppRoutes.choreList,
        builder: (context, state) => ChoreListScreen(
          householdId: state.pathParameters['householdId']!,
        ),
      ),
      GoRoute(
        path: '/households/:householdId/chores/create',
        // Must be registered under this name — `chore_card.dart`'s "Edit
        // series" action navigates via `context.pushNamed(AppRoutes.createChore, ...)`.
        name: AppRoutes.createChore,
        builder: (context, state) {
          final id = state.pathParameters['householdId']!;
          final initData = state.extra as ChoreFormInitData?;
          return CreateChoreScreen(householdId: id, initData: initData);
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      choresNotifierProvider.overrideWith(choresNotifier),
      householdsNotifierProvider.overrideWith(
        () => _DataHouseholdsNotifier(households ?? [_household()]),
      ),
      membersNotifierProvider.overrideWith(
        () => _FakeMembersNotifier(
          members ??
              [
                _member(userId: 'user-1', displayName: 'Alice', role: 'admin'),
                _member(userId: 'user-2', displayName: 'Bob'),
              ],
        ),
      ),
      currentUserProvider.overrideWith(
        (ref) async =>
            const UserProfile(id: _kCurrentUserId, displayName: 'Alice'),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Expands the test viewport so the whole form (down to the submit button)
/// fits without scrolling — without this, elements below ~600px cannot
/// receive tap events. Mirrors `create_chore_screen_test.dart`'s helper.
void _expandView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('Chore editing (TASK-060)', () {
    testWidgets('admin long-press shows "Edit series" alongside "Delete series"',
        (tester) async {
      final notifier = _TrackingChoresNotifier([_chore()]);
      await tester.pumpWidget(_buildApp(choresNotifier: () => notifier));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edit_series_menu_item')), findsOneWidget);
      expect(find.byKey(const Key('delete_series_menu_item')), findsOneWidget);
    });

    testWidgets('non-admin long-press shows no admin menu, so no edit action',
        (tester) async {
      final notifier = _TrackingChoresNotifier([_chore()]);
      await tester.pumpWidget(_buildApp(
        choresNotifier: () => notifier,
        households: [_household(role: 'member')],
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edit_series_menu_item')), findsNothing);
      expect(find.byKey(const Key('delete_series_menu_item')), findsNothing);
    });

    testWidgets(
        'tapping "Edit series" opens CreateChoreScreen pre-populated from the chore',
        (tester) async {
      final chore = _chore(
        title: 'Vacuum living room',
        description: 'Include under the couch',
        category: 'living_room',
        effortLevel: 'medium',
        choreType: 'one_off',
        dueDate: DateTime(2027, 8, 3),
      );
      final notifier = _TrackingChoresNotifier([chore]);
      await tester.pumpWidget(_buildApp(choresNotifier: () => notifier));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_series_menu_item')));
      await tester.pumpAndSettle();

      // Now on CreateChoreScreen in edit mode.
      expect(find.text('Edit Chore'), findsOneWidget);
      expect(find.byKey(const Key('edit_mode_banner')), findsOneWidget);

      final titleField =
          tester.widget<TextFormField>(find.byKey(const Key('title_field')));
      expect(titleField.controller!.text, 'Vacuum living room');

      final descriptionField = tester.widget<TextFormField>(
        find.byKey(const Key('description_field')),
      );
      expect(descriptionField.controller!.text, 'Include under the couch');

      final dateField = tester
          .widget<TextFormField>(find.byKey(const Key('due_date_field')));
      expect(dateField.controller!.text, isNotEmpty);
    });

    testWidgets(
        'saving an edit with an unchanged past due date succeeds and PATCHes the definition',
        (tester) async {
      _expandView(tester);
      // A due date that has already passed relative to "now" — the chore
      // existed before, its date just never got pushed forward.
      final pastDueDate = DateTime.now().subtract(const Duration(days: 10));
      final chore = _chore(dueDate: pastDueDate);
      final notifier = _TrackingChoresNotifier([chore]);
      await tester.pumpWidget(_buildApp(choresNotifier: () => notifier));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_series_menu_item')));
      await tester.pumpAndSettle();

      // Submit without touching the due-date field at all.
      await tester.tap(find.byKey(const Key('submit_button')));
      await tester.pumpAndSettle();

      // No validation error trapped the user on-screen...
      expect(find.text('Due date cannot be in the past'), findsNothing);

      // ...and the definition PATCH actually went through with the
      // original (still-past) date.
      expect(notifier.updateCalls, hasLength(1));
      expect(notifier.updateCalls.single.definitionId, 'def-c1');
      expect(
        notifier.updateCalls.single.body['first_due_date'],
        _formatDate(pastDueDate),
      );
    });

    testWidgets(
        'actively picking a new due date in edit mode is sent in the PATCH body',
        (tester) async {
      _expandView(tester);
      // Complements the "unchanged past date" test above: this drives the
      // date picker to actually change the value (`_dueDateManuallyChanged`
      // flips true), proving the relaxed validator doesn't also swallow a
      // deliberate date change.
      final pastDueDate = DateTime.now().subtract(const Duration(days: 10));
      final chore = _chore(dueDate: pastDueDate);
      final notifier = _TrackingChoresNotifier([chore]);
      await tester.pumpWidget(_buildApp(choresNotifier: () => notifier));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_series_menu_item')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('due_date_field')));
      await tester.pumpAndSettle();

      // Material date picker: confirm today's date (the default
      // `initialDate` for an already-past edit-mode value) via the "OK"
      // button.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Due date cannot be in the past'), findsNothing);
      expect(notifier.updateCalls, hasLength(1));

      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      expect(
        notifier.updateCalls.single.body['first_due_date'],
        _formatDate(todayOnly),
      );
      // The newly-picked date must not equal the original past due date.
      expect(
        notifier.updateCalls.single.body['first_due_date'],
        isNot(_formatDate(pastDueDate)),
      );
    });
  });
}

String _formatDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
