import 'dart:async';

import 'package:chore_app/features/household/models/household_model.dart';
import 'package:chore_app/features/household/providers/household_provider.dart';
import 'package:chore_app/features/leaderboard/models/leaderboard_model.dart';
import 'package:chore_app/features/leaderboard/providers/leaderboard_provider.dart';
import 'package:chore_app/features/leaderboard/screens/leaderboard_screen.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:chore_app/shared/widgets/error_widget.dart';
import 'package:chore_app/shared/widgets/loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Sample data helpers
// ---------------------------------------------------------------------------

const _householdId = 'hh-001';
const _currentUserId = 'user-alice';

LeaderboardEntry _entry({
  required int rank,
  required String userId,
  required String displayName,
  int points = 10,
  int choresCompleted = 1,
}) {
  return LeaderboardEntry(
    rank: rank,
    userId: userId,
    displayName: displayName,
    points: points,
    choresCompleted: choresCompleted,
  );
}

LeaderboardResult _result({
  List<LeaderboardEntry>? entries,
  LeaderboardScope scope = LeaderboardScope.allTime,
  String? weekStart,
  String? weekEnd,
  int? requestingUserRank,
}) {
  return LeaderboardResult(
    scope: scope,
    weekStart: weekStart,
    weekEnd: weekEnd,
    entries: entries ?? [],
    requestingUserRank: requestingUserRank,
  );
}

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

/// Avoids a real Dio network call from `householdsNotifierProvider`, which
/// [LeaderboardScreen] watches to determine `isAdmin`. Without this override
/// the request never resolves and leaves a pending timer at test teardown.
class _FakeHouseholdsNotifier extends HouseholdsNotifier {
  @override
  Future<List<HouseholdModel>> build() async => const [];
}

class _FixedScopeNotifier extends LeaderboardScopeNotifier {
  _FixedScopeNotifier(this._initial);
  final LeaderboardScope _initial;

  @override
  LeaderboardScope build() => _initial;
}

// ---------------------------------------------------------------------------
// Widget builder
// ---------------------------------------------------------------------------

/// Builds the [LeaderboardScreen] with a fully controlled provider scope.
///
/// [leaderboardOverride] controls what the [leaderboardProvider] returns.
/// [initialScope] sets the active scope tab.
/// [userId] overrides [currentUserIdProvider].
Widget buildLeaderboardScreen({
  AsyncValue<LeaderboardResult>? leaderboardOverride,
  LeaderboardScope initialScope = LeaderboardScope.allTime,
  String? userId = _currentUserId,
}) {
  // We need a GoRouter to satisfy context.go* calls in the bottom nav.
  final router = GoRouter(
    initialLocation: '/households/$_householdId/leaderboard',
    routes: [
      GoRoute(
        path: '/households/:householdId/leaderboard',
        builder: (_, state) => LeaderboardScreen(
          householdId: state.pathParameters['householdId']!,
        ),
      ),
      GoRoute(
        path: '/households/:householdId/chores',
        builder: (_, state) => Scaffold(
          body: Text('chores-${state.pathParameters['householdId']}'),
        ),
      ),
      GoRoute(
        path: '/households/:householdId/my-chores',
        builder: (_, state) => Scaffold(
          body: Text('my-chores-${state.pathParameters['householdId']}'),
        ),
      ),
    ],
  );

  final asyncValue =
      leaderboardOverride ?? AsyncValue.data(_result());

  return ProviderScope(
    overrides: [
      leaderboardProvider(_householdId).overrideWith(
        (ref) async {
          // Watch scope so tests can see re-fetch triggered.
          ref.watch(leaderboardScopeNotifierProvider);
          return asyncValue.when(
            data: (d) async => d,
            loading: () => Completer<LeaderboardResult>().future,
            error: (e, s) => Future.error(e, s),
          );
        },
      ),
      currentUserIdProvider.overrideWithValue(userId),
      leaderboardScopeNotifierProvider.overrideWith(
        () => _FixedScopeNotifier(initialScope),
      ),
      householdsNotifierProvider.overrideWith(_FakeHouseholdsNotifier.new),
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

void main() {
  group('LeaderboardScreen – scope selector', () {
    testWidgets('renders 3 scope segments', (tester) async {
      await tester.pumpWidget(buildLeaderboardScreen());
      await tester.pump();

      // The default (allTime) scope label also appears in the range-label
      // subtitle below the picker, so it can legitimately show up twice.
      expect(
        find.descendant(
          of: find.byKey(const Key('scope_selector')),
          matching: find.text('All Time'),
        ),
        findsOneWidget,
      );
      expect(find.text('This Week'), findsOneWidget);
      expect(find.text('This Month'), findsOneWidget);
    });

    testWidgets('scope selector widget is present', (tester) async {
      await tester.pumpWidget(buildLeaderboardScreen());
      await tester.pump();

      expect(find.byKey(const Key('scope_selector')), findsOneWidget);
    });

    testWidgets('tapping a different scope updates the notifier',
        (tester) async {
      // Use a real LeaderboardScopeNotifier (no scope override) but a fake
      // leaderboard provider so no network call is made.
      final router = GoRouter(
        initialLocation: '/households/$_householdId/leaderboard',
        routes: [
          GoRoute(
            path: '/households/:householdId/leaderboard',
            builder: (_, state) => LeaderboardScreen(
              householdId: state.pathParameters['householdId']!,
            ),
          ),
          GoRoute(
            path: '/households/:householdId/chores',
            builder: (_, __) => const Scaffold(body: Text('chores')),
          ),
          GoRoute(
            path: '/households/:householdId/my-chores',
            builder: (_, __) => const Scaffold(body: Text('my-chores')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leaderboardProvider(_householdId).overrideWith(
              (ref) async {
                ref.watch(leaderboardScopeNotifierProvider);
                return _result();
              },
            ),
            currentUserIdProvider.overrideWithValue(_currentUserId),
            householdsNotifierProvider
                .overrideWith(_FakeHouseholdsNotifier.new),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pump();

      // Read scope from the ProviderContainer attached to the screen element.
      final screenElement = tester.element(find.byType(LeaderboardScreen));
      final container = ProviderScope.containerOf(screenElement);

      expect(
        container.read(leaderboardScopeNotifierProvider),
        LeaderboardScope.allTime,
      );

      // Tap the "This Week" segment.
      await tester.tap(find.text('This Week'));
      await tester.pump();

      expect(
        container.read(leaderboardScopeNotifierProvider),
        LeaderboardScope.thisWeek,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Date range subtitle
  // -------------------------------------------------------------------------

  group('LeaderboardScreen – date range subtitle', () {
    testWidgets('shows date range when scope is thisWeek', (tester) async {
      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(
            _result(
              scope: LeaderboardScope.thisWeek,
              weekStart: '2026-06-22',
              weekEnd: '2026-06-28',
            ),
          ),
          initialScope: LeaderboardScope.thisWeek,
        ),
      );
      await tester.pump();

      expect(find.text('Jun 22 – Jun 28'), findsOneWidget);
    });

    testWidgets('does not show date range for allTime scope', (tester) async {
      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result()),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('date_range_subtitle')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Loading state
  // -------------------------------------------------------------------------

  group('LeaderboardScreen – loading state', () {
    testWidgets('shows LoadingWidget while data is loading', (tester) async {
      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: const AsyncValue.loading(),
        ),
      );
      await tester.pump();

      expect(find.byType(LoadingWidget), findsOneWidget);
      expect(find.byKey(const Key('loading_widget')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Error state
  // -------------------------------------------------------------------------

  group('LeaderboardScreen – error state', () {
    testWidgets('shows AppErrorWidget when provider errors', (tester) async {
      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.error(
            Exception('Network failure'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AppErrorWidget), findsOneWidget);
      expect(find.byKey(const Key('error_widget')), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('error widget has a Retry button', (tester) async {
      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.error(
            Exception('Timeout'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Rank styling — the podium redesign encodes 1st/2nd/3rd place via the
  // avatar's border colour (gold/silver/bronze) rather than a separate
  // circular badge. Ranks 4+ fall through to the plain `_RestList` rows.
  // -------------------------------------------------------------------------

  group('LeaderboardScreen – rank badge styling', () {
    testWidgets('rank 1 entry has a gold podium avatar border',
        (tester) async {
      final entries = [
        _entry(rank: 1, userId: 'u1', displayName: 'Alice', points: 100),
        _entry(rank: 2, userId: 'u2', displayName: 'Bob', points: 80),
        _entry(rank: 3, userId: 'u3', displayName: 'Carol', points: 60),
      ];

      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result(entries: entries)),
          userId: 'other-user',
        ),
      );
      await tester.pump();

      final avatar = find.byKey(const Key('podium_avatar_1'));
      expect(avatar, findsOneWidget);

      final container = tester.widget<Container>(avatar);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.border!.top.color, const Color(0xFFFBBF24));
    });

    testWidgets('rank 2 entry has a silver podium avatar border',
        (tester) async {
      final entries = [
        _entry(rank: 1, userId: 'u1', displayName: 'Alice', points: 100),
        _entry(rank: 2, userId: 'u2', displayName: 'Bob', points: 80),
      ];

      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result(entries: entries)),
          userId: 'other-user',
        ),
      );
      await tester.pump();

      final avatar = find.byKey(const Key('podium_avatar_2'));
      expect(avatar, findsOneWidget);

      final container = tester.widget<Container>(avatar);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      // Grey/slate tones have similar R/G/B channels.
      final color = decoration.border!.top.color;
      final r = (color.r * 255).round();
      final g = (color.g * 255).round();
      final b = (color.b * 255).round();
      final maxDiff = [
        (r - g).abs(),
        (g - b).abs(),
        (r - b).abs(),
      ].reduce((a, c) => a > c ? a : c);
      expect(maxDiff, lessThan(25));
    });

    testWidgets('rank 3 entry has a bronze podium avatar border',
        (tester) async {
      final entries = [
        _entry(rank: 1, userId: 'u1', displayName: 'Alice', points: 100),
        _entry(rank: 2, userId: 'u2', displayName: 'Bob', points: 80),
        _entry(rank: 3, userId: 'u3', displayName: 'Carol', points: 60),
      ];

      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result(entries: entries)),
          userId: 'other-user',
        ),
      );
      await tester.pump();

      final avatar = find.byKey(const Key('podium_avatar_3'));
      expect(avatar, findsOneWidget);

      final container = tester.widget<Container>(avatar);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.border!.top.color, const Color(0xFFE0B48C));
    });

    testWidgets('rank 4+ entry has no podium avatar', (tester) async {
      final entries = [
        _entry(rank: 1, userId: 'u1', displayName: 'Alice', points: 100),
        _entry(rank: 2, userId: 'u2', displayName: 'Bob', points: 80),
        _entry(rank: 3, userId: 'u3', displayName: 'Carol', points: 60),
        _entry(rank: 4, userId: 'u4', displayName: 'Dave', points: 40),
      ];

      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result(entries: entries)),
          userId: 'other-user',
        ),
      );
      await tester.pump();

      // Rank 4 falls into the plain rest-list, not the podium.
      expect(find.byKey(const Key('podium_avatar_4')), findsNothing);
      // But its rank number is still shown as plain text.
      expect(find.text('4'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Current user highlighting — the podium redesign marks the current user
  // with a "YOU" pill instead of a highlighted list-row background.
  // -------------------------------------------------------------------------

  group('LeaderboardScreen – current user highlighting', () {
    testWidgets('current user gets a "YOU" pill', (tester) async {
      final entries = [
        _entry(rank: 1, userId: _currentUserId, displayName: 'Alice', points: 85),
        _entry(rank: 2, userId: 'other-user', displayName: 'Bob', points: 40),
      ];

      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result(entries: entries)),
          userId: _currentUserId,
        ),
      );
      await tester.pump();

      expect(find.text('YOU'), findsOneWidget);
    });

    testWidgets('no "YOU" pill is shown when the viewer is not in the list',
        (tester) async {
      final entries = [
        _entry(rank: 1, userId: 'alice-id', displayName: 'Alice', points: 85),
        _entry(rank: 2, userId: 'other-user', displayName: 'Bob', points: 40),
      ];

      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result(entries: entries)),
          userId: 'nobody',
        ),
      );
      await tester.pump();

      expect(find.text('YOU'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Members with 0 points
  // -------------------------------------------------------------------------

  group('LeaderboardScreen – zero points members', () {
    testWidgets('members with 0 points appear in the list', (tester) async {
      final entries = [
        _entry(rank: 1, userId: 'u1', displayName: 'Alice', points: 50),
        _entry(rank: 2, userId: 'u2', displayName: 'Bob', points: 0),
        _entry(rank: 2, userId: 'u3', displayName: 'Carol', points: 0),
      ];

      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result(entries: entries)),
          userId: 'other',
        ),
      );
      await tester.pump();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
      expect(find.text('0 pts'), findsNWidgets(2));
    });
  });

  // -------------------------------------------------------------------------
  // Equal ranks
  // -------------------------------------------------------------------------

  group('LeaderboardScreen – equal ranks', () {
    testWidgets('two entries with same rank both show the same rank number',
        (tester) async {
      final entries = [
        _entry(rank: 1, userId: 'u1', displayName: 'Alice', points: 85),
        _entry(rank: 2, userId: 'u2', displayName: 'Bob', points: 40),
        _entry(rank: 2, userId: 'u3', displayName: 'Carol', points: 40),
      ];

      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result(entries: entries)),
          userId: 'other',
        ),
      );
      await tester.pump();

      // Both the 2nd and 3rd podium positions carry the same real rank (2),
      // so both pedestal labels should read "2".
      expect(find.byKey(const Key('podium_rank_2')), findsNWidgets(2));
    });
  });

  // -------------------------------------------------------------------------
  // Bottom navigation bar
  // -------------------------------------------------------------------------

  group('LeaderboardScreen – bottom nav bar', () {
    testWidgets('renders bottom navigation bar with 3 tabs', (tester) async {
      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result()),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('bottom_nav_bar')), findsOneWidget);
      // 'All Chores' and 'My Chores' only appear in the bottom nav.
      expect(find.text('All Chores'), findsOneWidget);
      expect(find.text('My Chores'), findsOneWidget);
      // 'Leaderboard' appears both in the AppBar title and the bottom nav tab.
      expect(find.text('Leaderboard'), findsAtLeastNWidgets(1));
    });

    testWidgets('Leaderboard tab is highlighted (index 2)', (tester) async {
      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result()),
        ),
      );
      await tester.pump();

      final nav = tester.widget<BottomNavigationBar>(
        find.byKey(const Key('bottom_nav_bar')),
      );
      expect(nav.currentIndex, 2);
    });
  });

  // -------------------------------------------------------------------------
  // Empty state
  // -------------------------------------------------------------------------

  group('LeaderboardScreen – empty state', () {
    testWidgets('shows empty state text when entries list is empty',
        (tester) async {
      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result(entries: [])),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('empty_state_text')), findsOneWidget);
    });
  });
}
