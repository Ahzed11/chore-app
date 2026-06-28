import 'dart:async';

import 'package:chore_app/features/auth/providers/current_user_provider.dart';
import 'package:chore_app/features/chores/models/chore_model.dart';
import 'package:chore_app/features/chores/providers/chores_provider.dart';
import 'package:chore_app/features/chores/screens/my_chores_screen.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:chore_app/shared/widgets/loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kHouseholdId = 'hh-1';
const _kCurrentUserId = 'user-1';
const _kOtherUserId = 'user-2';

// ---------------------------------------------------------------------------
// Data helpers
// ---------------------------------------------------------------------------

ChoreModel _chore({
  String id = 'c1',
  String title = 'Wash dishes',
  String status = 'pending',
  String effortLevel = 'medium',
  String category = 'kitchen',
  String? assigneeId = _kCurrentUserId,
  DateTime? dueDate,
  DateTime? completedAt,
  int? pointsAwarded,
}) {
  return ChoreModel(
    id: id,
    definitionId: 'def-$id',
    householdId: _kHouseholdId,
    assigneeId: assigneeId,
    assigneeName: assigneeId == _kCurrentUserId ? 'Test User' : null,
    assignedManually: false,
    dueDate: dueDate ?? DateTime(2026, 12, 31),
    status: status,
    completedAt: completedAt,
    pointsAwarded: pointsAwarded,
    title: title,
    category: category,
    effortLevel: effortLevel,
    choreType: 'recurring',
  );
}

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

class _FakeChoresNotifier extends ChoresNotifier {
  _FakeChoresNotifier(this._chores);

  final List<ChoreModel> _chores;

  @override
  Future<List<ChoreModel>> build(String arg) async => _chores;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> completeChore(String instanceId) async {
    // No-op: avoids real network calls in tests.
  }
}

class _LoadingChoresNotifier extends ChoresNotifier {
  @override
  Future<List<ChoreModel>> build(String arg) =>
      Completer<List<ChoreModel>>().future;
}

class _TrackingChoresNotifier extends _FakeChoresNotifier {
  _TrackingChoresNotifier(super.chores);

  final List<String> completedIds = [];

  @override
  Future<void> completeChore(String instanceId) async {
    completedIds.add(instanceId);
  }
}

// ---------------------------------------------------------------------------
// Widget builder helper
// ---------------------------------------------------------------------------

Widget _buildScreen({
  required List<ChoreModel> chores,
  String currentUserId = _kCurrentUserId,
  ChoresNotifier Function()? notifierFactory,
}) {
  return ProviderScope(
    overrides: [
      choresNotifierProvider.overrideWith(
        notifierFactory ?? () => _FakeChoresNotifier(chores),
      ),
      currentUserProvider.overrideWith(
        (ref) async =>
            UserProfile(id: currentUserId, displayName: 'Test User'),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const MyChoresScreen(householdId: _kHouseholdId),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Loading state
  // -------------------------------------------------------------------------

  group('MyChoresScreen – loading state', () {
    testWidgets('shows LoadingWidget while chores are loading', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          chores: [],
          notifierFactory: _LoadingChoresNotifier.new,
        ),
      );
      await tester.pump(); // single frame — provider still loading

      expect(find.byType(LoadingWidget), findsOneWidget);
      expect(find.text('Loading your chores...'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Points banner
  // -------------------------------------------------------------------------

  group('MyChoresScreen – points banner', () {
    testWidgets('renders points banner widget', (tester) async {
      await tester.pumpWidget(_buildScreen(chores: []));
      await tester.pump();

      expect(find.byKey(const Key('points_banner')), findsOneWidget);
    });

    testWidgets('shows zero pts when no completed chores', (tester) async {
      final chores = [
        _chore(id: 'c1', status: 'pending'),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      expect(find.byKey(const Key('points_banner')), findsOneWidget);
      expect(find.text('0 pts'), findsOneWidget);
    });

    testWidgets('sums pointsAwarded from complete chores only', (tester) async {
      final now = DateTime.now();
      final chores = [
        _chore(
          id: 'c1',
          status: 'complete',
          pointsAwarded: 25,
          dueDate: now.subtract(const Duration(days: 5)),
          completedAt: now.subtract(const Duration(days: 3)),
        ),
        _chore(
          id: 'c2',
          status: 'complete',
          pointsAwarded: 10,
          dueDate: now.subtract(const Duration(days: 4)),
          completedAt: now.subtract(const Duration(days: 2)),
        ),
        // pending chore — should NOT be counted
        _chore(id: 'c3', status: 'pending'),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      // 25 + 10 = 35
      expect(find.text('35 pts'), findsOneWidget);
    });

    testWidgets('excludes chores assigned to other users from points total',
        (tester) async {
      final now = DateTime.now();
      final chores = [
        // Current user: 50 pts
        _chore(
          id: 'c1',
          status: 'complete',
          assigneeId: _kCurrentUserId,
          pointsAwarded: 50,
          dueDate: now.subtract(const Duration(days: 3)),
          completedAt: now.subtract(const Duration(days: 1)),
        ),
        // Other user: should NOT be counted
        _chore(
          id: 'c2',
          status: 'complete',
          assigneeId: _kOtherUserId,
          pointsAwarded: 100,
          dueDate: now.subtract(const Duration(days: 3)),
          completedAt: now.subtract(const Duration(days: 1)),
        ),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      expect(find.text('50 pts'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Sort order
  // -------------------------------------------------------------------------

  group('MyChoresScreen – sort order', () {
    testWidgets(
        'renders overdue before pending before complete (vertical order)',
        (tester) async {
      // Increase viewport to ensure all 3 cards are rendered at once.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      // Provide chores in reverse order to verify the screen re-sorts them.
      final chores = [
        _chore(
          id: 'c_complete',
          title: 'Complete chore',
          status: 'complete',
          dueDate: now.subtract(const Duration(days: 5)),
          completedAt: now.subtract(const Duration(days: 3)),
          pointsAwarded: 25,
        ),
        _chore(
          id: 'c_pending',
          title: 'Pending chore',
          status: 'pending',
          dueDate: now.add(const Duration(days: 3)),
        ),
        _chore(
          id: 'c_overdue',
          title: 'Overdue chore',
          status: 'overdue',
          dueDate: now.subtract(const Duration(days: 2)),
        ),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      final overdueY = tester
          .getTopLeft(find.byKey(const Key('my_chore_card_c_overdue')))
          .dy;
      final pendingY = tester
          .getTopLeft(find.byKey(const Key('my_chore_card_c_pending')))
          .dy;
      final completeY = tester
          .getTopLeft(find.byKey(const Key('my_chore_card_c_complete')))
          .dy;

      expect(overdueY, lessThan(pendingY),
          reason: 'Overdue must appear above pending');
      expect(pendingY, lessThan(completeY),
          reason: 'Pending must appear above complete');
    });

    testWidgets('sorts two overdue chores by dueDate ASC', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final chores = [
        // older overdue — due 5 days ago
        _chore(
          id: 'c_overdue_late',
          status: 'overdue',
          dueDate: now.subtract(const Duration(days: 5)),
        ),
        // more recent overdue — due 1 day ago
        _chore(
          id: 'c_overdue_early',
          status: 'overdue',
          dueDate: now.subtract(const Duration(days: 1)),
        ),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      final lateY = tester
          .getTopLeft(find.byKey(const Key('my_chore_card_c_overdue_late')))
          .dy;
      final earlyY = tester
          .getTopLeft(find.byKey(const Key('my_chore_card_c_overdue_early')))
          .dy;

      // "Due 5 days ago" has an older dueDate → should appear first (lower Y).
      expect(lateY, lessThan(earlyY));
    });

    testWidgets('pending chore with past due date sorts with overdue group',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final chores = [
        // status=pending but dueDate in the past → isOverdue==true
        _chore(
          id: 'c_past_pending',
          status: 'pending',
          dueDate: now.subtract(const Duration(days: 3)),
        ),
        // normal pending (future)
        _chore(
          id: 'c_future_pending',
          status: 'pending',
          dueDate: now.add(const Duration(days: 7)),
        ),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      final pastY = tester
          .getTopLeft(find.byKey(const Key('my_chore_card_c_past_pending')))
          .dy;
      final futureY = tester
          .getTopLeft(find.byKey(const Key('my_chore_card_c_future_pending')))
          .dy;

      // Past-due pending is "overdue" so it should sort before future pending.
      expect(pastY, lessThan(futureY));
    });
  });

  // -------------------------------------------------------------------------
  // "Mark as done" button visibility
  // -------------------------------------------------------------------------

  group('MyChoresScreen – mark as done button', () {
    testWidgets('button visible for pending chore', (tester) async {
      final chores = [
        _chore(
          id: 'c1',
          status: 'pending',
          dueDate: DateTime(2027, 6, 30),
        ),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      expect(find.byKey(const Key('mark_done_button_c1')), findsOneWidget);
    });

    testWidgets('button visible for overdue chore', (tester) async {
      final now = DateTime.now();
      final chores = [
        _chore(
          id: 'c1',
          status: 'overdue',
          dueDate: now.subtract(const Duration(days: 2)),
        ),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      expect(find.byKey(const Key('mark_done_button_c1')), findsOneWidget);
    });

    testWidgets('button hidden for complete chore', (tester) async {
      final now = DateTime.now();
      final chores = [
        _chore(
          id: 'c1',
          status: 'complete',
          dueDate: now.subtract(const Duration(days: 5)),
          completedAt: now.subtract(const Duration(days: 3)),
          pointsAwarded: 25,
        ),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      expect(find.byKey(const Key('mark_done_button_c1')), findsNothing);
    });

    testWidgets(
        'shows button for pending and overdue but not complete in mixed list',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final chores = [
        _chore(
          id: 'c_pending',
          status: 'pending',
          dueDate: now.add(const Duration(days: 3)),
        ),
        _chore(
          id: 'c_overdue',
          status: 'overdue',
          dueDate: now.subtract(const Duration(days: 1)),
        ),
        _chore(
          id: 'c_complete',
          status: 'complete',
          dueDate: now.subtract(const Duration(days: 5)),
          completedAt: now.subtract(const Duration(days: 3)),
          pointsAwarded: 10,
        ),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      expect(find.byKey(const Key('mark_done_button_c_pending')), findsOneWidget);
      expect(find.byKey(const Key('mark_done_button_c_overdue')), findsOneWidget);
      expect(find.byKey(const Key('mark_done_button_c_complete')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Completion info for complete chores
  // -------------------------------------------------------------------------

  group('MyChoresScreen – completion info', () {
    testWidgets('shows completion date and points for a complete chore',
        (tester) async {
      final chores = [
        _chore(
          id: 'c1',
          status: 'complete',
          dueDate: DateTime(2026, 6, 20),
          completedAt: DateTime(2026, 6, 25),
          pointsAwarded: 25,
        ),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      final infoKey = find.byKey(const Key('completion_info_c1'));
      expect(infoKey, findsOneWidget);
      final text = tester.widget<Text>(infoKey).data ?? '';
      expect(text, contains('Jun 25'));
      expect(text, contains('25 pts'));
    });
  });

  // -------------------------------------------------------------------------
  // Empty state
  // -------------------------------------------------------------------------

  group('MyChoresScreen – empty state', () {
    testWidgets('shows empty text when no chores are assigned to user',
        (tester) async {
      // All chores belong to a different user.
      final chores = [
        _chore(id: 'c1', assigneeId: _kOtherUserId),
        _chore(id: 'c2', assigneeId: _kOtherUserId),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      expect(
        find.byKey(const Key('empty_state_my_chores')),
        findsOneWidget,
      );
      expect(
        find.text('No chores assigned to you yet.'),
        findsOneWidget,
      );
    });

    testWidgets('shows empty text when global chore list is empty',
        (tester) async {
      await tester.pumpWidget(_buildScreen(chores: []));
      await tester.pump();

      expect(
        find.text('No chores assigned to you yet.'),
        findsOneWidget,
      );
    });

    testWidgets('points banner still shows with 0 pts on empty state',
        (tester) async {
      await tester.pumpWidget(_buildScreen(chores: []));
      await tester.pump();

      expect(find.byKey(const Key('points_banner')), findsOneWidget);
      expect(find.text('0 pts'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Only current user's chores are shown
  // -------------------------------------------------------------------------

  group('MyChoresScreen – user filtering', () {
    testWidgets('only shows chores assigned to the current user',
        (tester) async {
      final chores = [
        _chore(id: 'c1', title: 'My chore', assigneeId: _kCurrentUserId),
        _chore(id: 'c2', title: 'Other chore', assigneeId: _kOtherUserId),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      expect(find.text('My chore'), findsOneWidget);
      expect(find.text('Other chore'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Confirmation bottom sheet
  // -------------------------------------------------------------------------

  group('MyChoresScreen – complete confirmation sheet', () {
    testWidgets('tapping "Mark as done" shows the confirmation sheet',
        (tester) async {
      final chores = [
        _chore(
          id: 'c1',
          title: 'Clean bathroom',
          status: 'pending',
          effortLevel: 'hard',
          dueDate: DateTime(2027, 3, 1),
        ),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      await tester.tap(find.byKey(const Key('mark_done_button_c1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('complete_sheet_title')), findsOneWidget);
      // Title appears in both the card and the sheet body.
      expect(find.text('Clean bathroom'), findsAtLeastNWidgets(1));
    });

    testWidgets('confirmation sheet displays points to be earned',
        (tester) async {
      final chores = [
        _chore(
          id: 'c1',
          title: 'Vacuum',
          status: 'pending',
          effortLevel: 'medium', // 25 pts
          dueDate: DateTime(2027, 3, 1),
        ),
      ];

      await tester.pumpWidget(_buildScreen(chores: chores));
      await tester.pump();

      await tester.tap(find.byKey(const Key('mark_done_button_c1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('confirm_points_text')), findsOneWidget);
      final text = tester
          .widget<Text>(find.byKey(const Key('confirm_points_text')))
          .data ?? '';
      expect(text, contains('25 points'));
    });

    testWidgets('tapping Cancel dismisses the sheet without completing',
        (tester) async {
      final notifier = _TrackingChoresNotifier([
        _chore(
          id: 'c1',
          status: 'pending',
          dueDate: DateTime(2027, 3, 1),
        ),
      ]);

      await tester.pumpWidget(
        _buildScreen(
          chores: [],
          notifierFactory: () => notifier,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('mark_done_button_c1')));
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.byKey(const Key('confirm_cancel_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('complete_sheet_title')), findsNothing);
      expect(notifier.completedIds, isEmpty);
    });

    testWidgets(
        'tapping Complete in the sheet calls completeChore on the notifier',
        (tester) async {
      final notifier = _TrackingChoresNotifier([
        _chore(
          id: 'c1',
          status: 'pending',
          dueDate: DateTime(2027, 3, 1),
        ),
      ]);

      await tester.pumpWidget(
        _buildScreen(
          chores: [],
          notifierFactory: () => notifier,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('mark_done_button_c1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_done_button')));
      await tester.pumpAndSettle();

      expect(notifier.completedIds, contains('c1'));
    });
  });

  // -------------------------------------------------------------------------
  // Bottom navigation bar
  // -------------------------------------------------------------------------

  group('MyChoresScreen – bottom nav bar', () {
    testWidgets('renders bottom nav bar with 3 tabs', (tester) async {
      await tester.pumpWidget(_buildScreen(chores: []));
      await tester.pump();

      expect(find.byKey(const Key('bottom_nav_bar')), findsOneWidget);
      expect(find.text('All Chores'), findsOneWidget);
      expect(find.text('My Chores'), findsAtLeastNWidgets(1));
      expect(find.text('Leaderboard'), findsOneWidget);
    });

    testWidgets('"My Chores" tab is highlighted at index 1', (tester) async {
      await tester.pumpWidget(_buildScreen(chores: []));
      await tester.pump();

      final nav = tester.widget<BottomNavigationBar>(
        find.byKey(const Key('bottom_nav_bar')),
      );
      expect(nav.currentIndex, 1);
    });
  });
}
