import 'dart:async';

import 'package:chore_app/features/auth/providers/current_user_provider.dart';
import 'package:chore_app/features/chores/models/chore_model.dart';
import 'package:chore_app/features/chores/providers/chores_provider.dart';
import 'package:chore_app/features/chores/screens/chore_list_screen.dart';
import 'package:chore_app/features/chores/widgets/chore_card.dart';
import 'package:chore_app/features/household/models/household_model.dart';
import 'package:chore_app/features/household/models/member_model.dart';
import 'package:chore_app/features/household/providers/household_provider.dart';
import 'package:chore_app/features/household/providers/members_provider.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:chore_app/shared/widgets/loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _kHouseholdId = 'hh-1';
const _kCurrentUserId = 'user-1';

ChoreModel _chore({
  String id = 'c1',
  String title = 'Wash dishes',
  String status = 'pending',
  String effortLevel = 'easy',
  String category = 'kitchen',
  String? assigneeId,
  String? assigneeName,
  DateTime? dueDate,
}) {
  return ChoreModel(
    id: id,
    definitionId: 'def-$id',
    householdId: _kHouseholdId,
    assigneeId: assigneeId,
    assigneeName: assigneeName,
    assignedManually: false,
    dueDate: dueDate ?? DateTime(2026, 6, 25),
    status: status,
    title: title,
    category: category,
    effortLevel: effortLevel,
    choreType: 'recurring',
  );
}

HouseholdModel _household({
  String id = _kHouseholdId,
  String name = 'Test Home',
  String role = 'admin',
}) {
  return HouseholdModel(
    id: id,
    name: name,
    role: role,
    memberCount: 2,
    createdAt: DateTime(2025, 1, 1),
  );
}

// ---------------------------------------------------------------------------
// Fake user profile provider override
// ---------------------------------------------------------------------------

/// A provider key that can be overridden in tests. We expose a thin wrapper
/// around the private `_currentUserProvider` by re-exporting it through a
/// testable public provider that the screen reads through a function.
///
/// Because `_currentUserProvider` is private to the screen file we use a
/// different strategy: we inject a known Provider<AsyncValue<...>> through
/// ProviderScope overrides that shadows the real provider.
///
/// The simplest approach: override `_currentUserProvider` indirectly by
/// providing our own `FutureProvider` with the same family key.  Since the
/// private provider is module-scoped and inaccessible from tests, we can't
/// directly override it.  Instead, the screen should expose a way to inject
/// the user.  For this test we rely on the fact that the screen only uses the
/// user ID for the "My Chores" toggle — so we test that independently.

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

class _DataChoresNotifier extends ChoresNotifier {
  _DataChoresNotifier(this._chores);
  final List<ChoreModel> _chores;

  @override
  Future<List<ChoreModel>> build(String arg) async => _chores;

  @override
  Future<void> refresh() async {
    // no-op for most tests — refreshCallCount test uses subclass
  }
}

class _LoadingChoresNotifier extends ChoresNotifier {
  @override
  Future<List<ChoreModel>> build(String arg) =>
      Completer<List<ChoreModel>>().future;
}

class _ErrorChoresNotifier extends ChoresNotifier {
  _ErrorChoresNotifier(this._message);
  final String _message;

  @override
  Future<List<ChoreModel>> build(String arg) =>
      Future.error(Exception(_message));
}

class _TrackingChoresNotifier extends _DataChoresNotifier {
  _TrackingChoresNotifier(super.chores);
  int refreshCallCount = 0;

  @override
  Future<void> refresh() async {
    refreshCallCount++;
  }
}

class _DataHouseholdsNotifier extends HouseholdsNotifier {
  _DataHouseholdsNotifier(this._households);
  final List<HouseholdModel> _households;

  @override
  Future<List<HouseholdModel>> build() async => _households;
}

class _FakeMembersNotifier extends MembersNotifier {
  @override
  Future<List<MemberModel>> build(String arg) async => const [];
}

// ---------------------------------------------------------------------------
// Widget builder helpers
// ---------------------------------------------------------------------------

Widget _buildScreen({
  required ChoresNotifier Function() choresNotifier,
  List<HouseholdModel>? households,
  ChoreFilter initialFilter = const ChoreFilter(),
  String currentUserId = _kCurrentUserId,
}) {
  return ProviderScope(
    overrides: [
      choresNotifierProvider.overrideWith(choresNotifier),
      householdsNotifierProvider.overrideWith(
        () => _DataHouseholdsNotifier(households ?? [_household()]),
      ),
      membersNotifierProvider.overrideWith(_FakeMembersNotifier.new),
      choreFilterNotifierProvider.overrideWith(
        () => _FixedFilterNotifier(initialFilter),
      ),
      currentUserProvider.overrideWith(
        (ref) async => UserProfile(id: currentUserId, displayName: 'Test User'),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const ChoreListScreen(householdId: _kHouseholdId),
    ),
  );
}

class _FixedFilterNotifier extends ChoreFilterNotifier {
  _FixedFilterNotifier(this._initial);
  final ChoreFilter _initial;

  @override
  ChoreFilter build() => _initial;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChoreListScreen', () {
    // -------------------------------------------------------------------------
    // Loading state
    // -------------------------------------------------------------------------
    testWidgets('shows LoadingWidget while chores are loading', (tester) async {
      await tester.pumpWidget(
        _buildScreen(choresNotifier: _LoadingChoresNotifier.new),
      );
      await tester.pump(); // single frame — keep in loading

      expect(find.byType(LoadingWidget), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // List renders correctly
    // -------------------------------------------------------------------------
    testWidgets('renders 3 ChoreCard widgets when 3 chores are returned',
        (tester) async {
      final chores = [
        _chore(id: 'c1', title: 'Wash dishes'),
        _chore(id: 'c2', title: 'Vacuum living room', category: 'living_room'),
        _chore(id: 'c3', title: 'Mow the lawn', category: 'garden_outdoor'),
      ];
      await tester.pumpWidget(
        _buildScreen(choresNotifier: () => _DataChoresNotifier(chores)),
      );
      await tester.pump();

      expect(find.byType(ChoreCard), findsNWidgets(3));
      expect(find.text('Wash dishes'), findsOneWidget);
      expect(find.text('Vacuum living room'), findsOneWidget);
      expect(find.text('Mow the lawn'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Overdue chore shows red warning icon
    // -------------------------------------------------------------------------
    testWidgets('overdue chore shows red warning icon', (tester) async {
      final chores = [
        _chore(
          id: 'c1',
          title: 'Overdue task',
          status: 'overdue',
          dueDate: DateTime(2025, 1, 1), // past date
        ),
      ];
      await tester.pumpWidget(
        _buildScreen(choresNotifier: () => _DataChoresNotifier(chores)),
      );
      await tester.pump();

      expect(find.byIcon(Icons.priority_high), findsOneWidget);
    });

    testWidgets('non-overdue chore does not show warning icon', (tester) async {
      final chores = [
        _chore(
          id: 'c1',
          title: 'Future task',
          status: 'pending',
          dueDate: DateTime(2027, 12, 31),
        ),
      ];
      await tester.pumpWidget(
        _buildScreen(choresNotifier: () => _DataChoresNotifier(chores)),
      );
      await tester.pump();

      expect(find.byIcon(Icons.priority_high), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Status filter tabs
    // -------------------------------------------------------------------------
    testWidgets('status filter tabs are present', (tester) async {
      await tester.pumpWidget(
        _buildScreen(choresNotifier: () => _DataChoresNotifier([])),
      );
      await tester.pump();

      // The filter row renders GestureDetector+Text tabs, not FilterChips.
      // Labels come from const _filterTabs = ['All', 'Pending', 'Overdue', 'Done'].
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('Pending filter tab can be tapped', (tester) async {
      await tester.pumpWidget(
        _buildScreen(choresNotifier: () => _DataChoresNotifier([])),
      );
      await tester.pump();

      // Tap the Pending tab text.
      await tester.tap(find.text('Pending'));
      await tester.pump();

      // The empty state for the 'pending' filter shows 'Nothing pending',
      // confirming the tap changed the active filter.
      expect(find.text('Nothing pending'), findsOneWidget);
    });

    testWidgets('"All" filter tab is active by default', (tester) async {
      // Provide both a pending and a complete chore. If the default filter
      // were anything other than 'all', at least one would be hidden.
      final chores = [
        _chore(
          id: 'c1',
          title: 'Pending chore',
          status: 'pending',
          dueDate: DateTime(2027, 1, 1),
        ),
        _chore(id: 'c2', title: 'Done chore', status: 'complete'),
      ];
      await tester.pumpWidget(
        _buildScreen(choresNotifier: () => _DataChoresNotifier(chores)),
      );
      await tester.pump();

      // Both chores visible → the 'all' filter is active by default.
      expect(find.text('Pending chore'), findsOneWidget);
      expect(find.text('Done chore'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // "My Chores" bottom navigation item is present
    // -------------------------------------------------------------------------
    testWidgets('"My Chores" bottom nav item is present', (tester) async {
      await tester.pumpWidget(
        _buildScreen(choresNotifier: () => _DataChoresNotifier([])),
      );
      await tester.pump();

      // 'My Chores' is now a BottomNavigationBarItem, not a chip.
      expect(find.text('My Chores'), findsOneWidget);
    });

    testWidgets('"My Chores" label is visible in the bottom navigation bar',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(choresNotifier: () => _DataChoresNotifier([])),
      );
      await tester.pump();

      // 'My Chores' appears as a label in the bottom navigation bar.
      expect(find.text('My Chores'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Admin FAB visible; Member FAB is hidden
    // -------------------------------------------------------------------------
    testWidgets('Admin sees FAB with add_task icon', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          choresNotifier: () => _DataChoresNotifier([]),
          households: [_household(role: 'admin')],
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('add_chore_fab')), findsOneWidget);
    });

    testWidgets('Member does not see FAB', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          choresNotifier: () => _DataChoresNotifier([]),
          households: [_household(role: 'member')],
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('add_chore_fab')), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Pull-to-refresh calls refresh
    // -------------------------------------------------------------------------
    testWidgets('pull-to-refresh triggers refresh on the notifier',
        (tester) async {
      final notifier = _TrackingChoresNotifier([
        _chore(id: 'c1', title: 'Test chore'),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            choresNotifierProvider.overrideWith(() => notifier),
            householdsNotifierProvider.overrideWith(
              () => _DataHouseholdsNotifier([_household()]),
            ),
            membersNotifierProvider.overrideWith(_FakeMembersNotifier.new),
            choreFilterNotifierProvider.overrideWith(
              () => _FixedFilterNotifier(const ChoreFilter()),
            ),
            currentUserProvider.overrideWith(
              (ref) async => const UserProfile(
                id: _kCurrentUserId,
                displayName: 'Test User',
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ChoreListScreen(householdId: _kHouseholdId),
          ),
        ),
      );
      await tester.pump();

      // Simulate pull-to-refresh gesture.
      await tester.drag(
        find.byKey(const Key('chore_list')),
        const Offset(0, 300),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(notifier.refreshCallCount, greaterThanOrEqualTo(1));
    });

    // -------------------------------------------------------------------------
    // Empty state
    // -------------------------------------------------------------------------
    testWidgets('shows empty state when no chores returned', (tester) async {
      await tester.pumpWidget(
        _buildScreen(choresNotifier: () => _DataChoresNotifier([])),
      );
      await tester.pump();

      expect(find.text('All clear!'), findsOneWidget);
      expect(find.byKey(const Key('empty_state_icon')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Bottom navigation bar
    // -------------------------------------------------------------------------
    testWidgets('renders BottomNavigationBar with 3 tabs', (tester) async {
      await tester.pumpWidget(
        _buildScreen(choresNotifier: () => _DataChoresNotifier([])),
      );
      await tester.pump();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('All Chores'), findsOneWidget);
      expect(find.text('My Chores'), findsAtLeastNWidgets(1));
      expect(find.text('Leaderboard'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Error state
    // -------------------------------------------------------------------------
    testWidgets('shows error widget when chores provider errors', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          choresNotifier: () => _ErrorChoresNotifier('Server error'),
        ),
      );
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Client-side filtering
    // -------------------------------------------------------------------------
    testWidgets('only shows pending chores when pending filter active',
        (tester) async {
      final chores = [
        // Future due date keeps isOverdue == false so the pending filter shows it.
        _chore(
          id: 'c1',
          title: 'Pending task',
          status: 'pending',
          dueDate: DateTime(2027, 12, 31),
        ),
        _chore(id: 'c2', title: 'Complete task', status: 'complete'),
      ];

      await tester.pumpWidget(
        _buildScreen(
          choresNotifier: () => _DataChoresNotifier(chores),
        ),
      );
      await tester.pump();

      // The screen uses local state for filtering; tap the tab to activate it.
      await tester.tap(find.text('Pending'));
      await tester.pump();

      expect(find.text('Pending task'), findsOneWidget);
      expect(find.text('Complete task'), findsNothing);
    });

    testWidgets('household name is shown in app bar', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          choresNotifier: () => _DataChoresNotifier([]),
          households: [_household(name: 'Smith Family')],
        ),
      );
      await tester.pump();

      expect(find.text('Smith Family'), findsOneWidget);
    });
  });
}
