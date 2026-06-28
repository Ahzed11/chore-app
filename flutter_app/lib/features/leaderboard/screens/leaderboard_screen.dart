import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../router/app_router.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../models/leaderboard_model.dart';
import '../providers/leaderboard_provider.dart';
import '../widgets/leaderboard_entry_tile.dart';

// ---------------------------------------------------------------------------
// Date formatting helper
// ---------------------------------------------------------------------------

/// Formats "2026-06-22" → "Jun 22".
String _formatDate(String iso) {
  final date = DateTime.parse(iso);
  return DateFormat('MMM d').format(date);
}

// ---------------------------------------------------------------------------
// LeaderboardScreen
// ---------------------------------------------------------------------------

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key, required this.householdId});

  final String householdId;

  static const int _navIndex = 2;

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  static const _scopes = [
    LeaderboardScope.thisWeek,
    LeaderboardScope.thisMonth,
    LeaderboardScope.allTime,
  ];

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initialScope = ref.read(leaderboardScopeNotifierProvider);
    _tabController = TabController(
      length: _scopes.length,
      vsync: this,
      initialIndex: _scopes.indexOf(initialScope),
    );
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    ref
        .read(leaderboardScopeNotifierProvider.notifier)
        .setScope(_scopes[_tabController.index]);
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(leaderboardScopeNotifierProvider);
    final leaderboardAsync =
        ref.watch(leaderboardProvider(widget.householdId));
    final currentUserId = ref.watch(currentUserIdProvider);

    // Keep tab in sync if scope was changed externally.
    final scopeIndex = _scopes.indexOf(scope);
    if (_tabController.index != scopeIndex) {
      _tabController.animateTo(scopeIndex);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      // Tab selector sits above the main nav bar, always reachable at the bottom.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.calendar_view_week), text: 'This Week'),
              Tab(icon: Icon(Icons.calendar_month), text: 'This Month'),
              Tab(icon: Icon(Icons.all_inclusive), text: 'All Time'),
            ],
          ),
          _LeaderboardBottomNav(
            householdId: widget.householdId,
            currentIndex: LeaderboardScreen._navIndex,
          ),
        ],
      ),
      body: Column(
        children: [
          // Contextual subtitle: date range for week, month name for month.
          leaderboardAsync.when(
            data: (result) {
              String? label;
              if (scope == LeaderboardScope.thisWeek &&
                  result.weekStart != null &&
                  result.weekEnd != null) {
                label =
                    '${_formatDate(result.weekStart!)} – ${_formatDate(result.weekEnd!)}';
              } else if (scope == LeaderboardScope.thisMonth &&
                  result.monthStart != null) {
                label = DateFormat('MMMM yyyy')
                    .format(DateTime.parse(result.monthStart!));
              }
              if (label == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  key: const Key('date_range_subtitle'),
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          Expanded(
            child: leaderboardAsync.when(
              data: (result) {
                if (result.entries.isEmpty) {
                  return const Center(
                    child: Text(
                      key: Key('empty_state_text'),
                      'No entries yet. Complete some chores to get on the board!',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.builder(
                  key: const Key('leaderboard_list'),
                  itemCount: result.entries.length,
                  itemBuilder: (context, index) {
                    final entry = result.entries[index];
                    return LeaderboardEntryTile(
                      entry: entry,
                      isCurrentUser: entry.userId == currentUserId,
                    );
                  },
                );
              },
              loading: () => const LoadingWidget(
                key: Key('loading_widget'),
                message: 'Loading leaderboard…',
              ),
              error: (error, _) => AppErrorWidget(
                key: const Key('error_widget'),
                message: error.toString(),
                onRetry: () =>
                    ref.invalidate(leaderboardProvider(widget.householdId)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom navigation bar
// ---------------------------------------------------------------------------

class _LeaderboardBottomNav extends StatelessWidget {
  const _LeaderboardBottomNav({
    required this.householdId,
    required this.currentIndex,
  });

  final String householdId;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      key: const Key('bottom_nav_bar'),
      currentIndex: currentIndex,
      onTap: (index) {
        switch (index) {
          case 0:
            context.goNamed(
              AppRoutes.choreList,
              pathParameters: {'householdId': householdId},
            );
          case 1:
            context.goNamed(
              AppRoutes.myChores,
              pathParameters: {'householdId': householdId},
            );
          case 2:
            break; // Already on leaderboard.
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.checklist_rounded),
          label: 'All Chores',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_rounded),
          label: 'My Chores',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.leaderboard_rounded),
          label: 'Leaderboard',
        ),
      ],
    );
  }
}
