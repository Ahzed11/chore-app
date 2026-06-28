import 'dart:async';

import 'package:chore_app/features/leaderboard/models/leaderboard_model.dart';
import 'package:chore_app/features/leaderboard/providers/leaderboard_provider.dart';
import 'package:chore_app/features/leaderboard/screens/leaderboard_screen.dart';
import 'package:chore_app/features/leaderboard/widgets/leaderboard_entry_tile.dart';
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
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Fixed scope notifier for tests that need a specific initial scope
// ---------------------------------------------------------------------------

class _FixedScopeNotifier extends LeaderboardScopeNotifier {
  _FixedScopeNotifier(this._initial);
  final LeaderboardScope _initial;

  @override
  LeaderboardScope build() => _initial;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LeaderboardScreen – scope selector', () {
    testWidgets('renders 3 scope segments', (tester) async {
      await tester.pumpWidget(buildLeaderboardScreen());
      await tester.pump();

      // SegmentedButton renders each segment as a button-like widget.
      // The label texts should all be present.
      expect(find.text('All Time'), findsOneWidget);
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
  // Rank styling
  // -------------------------------------------------------------------------

  group('LeaderboardScreen – rank badge styling', () {
    testWidgets('rank 1 entry has a gold circular badge', (tester) async {
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

      // The badge for rank 1 has Key('rank_badge_1').
      final badge1 = find.byKey(const Key('rank_badge_1'));
      expect(badge1, findsOneWidget);

      // Verify it is a Container with a circular BoxDecoration using amber.
      final container = tester.widget<Container>(badge1);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      // Colors.amber is a MaterialColor; its value is 0xFFFFC107.
      expect(decoration.color, Colors.amber);
    });

    testWidgets('rank 2 entry has a silver circular badge', (tester) async {
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

      final badge2 = find.byKey(const Key('rank_badge_2'));
      expect(badge2, findsOneWidget);

      final container = tester.widget<Container>(badge2);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      // Grey.shade400 has similar R/G/B channels.
      final color = decoration.color!;
      final r = (color.r * 255).round();
      final g = (color.g * 255).round();
      final b = (color.b * 255).round();
      final maxDiff = [
        (r - g).abs(),
        (g - b).abs(),
        (r - b).abs(),
      ].reduce((a, c) => a > c ? a : c);
      expect(maxDiff, lessThan(20));
    });

    testWidgets('rank 3 entry has a bronze circular badge', (tester) async {
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

      final badge3 = find.byKey(const Key('rank_badge_3'));
      expect(badge3, findsOneWidget);

      final container = tester.widget<Container>(badge3);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, const Color(0xFFCD7F32));
    });

    testWidgets('rank 4+ entry has no circular badge', (tester) async {
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

      // No Key for rank 4 badge means no circular badge exists.
      expect(find.byKey(const Key('rank_badge_4')), findsNothing);
      // But the text '4' should still appear somewhere (the plain text label).
      expect(find.text('4'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Current user highlighting
  // -------------------------------------------------------------------------

  group('LeaderboardScreen – current user highlighting', () {
    testWidgets('current user row has highlighted background',
        (tester) async {
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

      // The tile for the current user uses ValueKey with the userId.
      final currentUserTile = find.byKey(
        const ValueKey('leaderboard_entry_$_currentUserId'),
      );
      expect(currentUserTile, findsOneWidget);

      // The container has a non-null color (the highlight).
      final container = tester.widget<Container>(currentUserTile);
      expect(container.color, isNotNull);
    });

    testWidgets('other user row has no highlighted background',
        (tester) async {
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

      final otherTile = find.byKey(
        const ValueKey('leaderboard_entry_other-user'),
      );
      expect(otherTile, findsOneWidget);

      final container = tester.widget<Container>(otherTile);
      // No highlight color for non-current-user.
      expect(container.color, isNull);
    });

    testWidgets('current user display name is bold', (tester) async {
      final entries = [
        _entry(rank: 1, userId: _currentUserId, displayName: 'Alice'),
        _entry(rank: 2, userId: 'bob-id', displayName: 'Bob'),
      ];

      await tester.pumpWidget(
        buildLeaderboardScreen(
          leaderboardOverride: AsyncValue.data(_result(entries: entries)),
          userId: _currentUserId,
        ),
      );
      await tester.pump();

      // Find the tile widget for the current user.
      final tiles = tester.widgetList<LeaderboardEntryTile>(
        find.byType(LeaderboardEntryTile),
      );
      final currentUserTile = tiles.firstWhere(
        (t) => t.entry.userId == _currentUserId,
      );
      expect(currentUserTile.isCurrentUser, isTrue);
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

      // Two entries at rank 2 → two silver badges.
      expect(find.byKey(const Key('rank_badge_2')), findsNWidgets(2));
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
