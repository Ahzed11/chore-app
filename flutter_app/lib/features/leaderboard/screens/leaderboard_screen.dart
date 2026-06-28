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

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key, required this.householdId});

  final String householdId;

  // Bottom-nav tab index for this screen.
  static const int _tabIndex = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(leaderboardScopeNotifierProvider);
    final leaderboardAsync = ref.watch(leaderboardProvider(householdId));
    final currentUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: Column(
        children: [
          // ----------------------------------------------------------------
          // Scope selector
          // ----------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _ScopeSelector(
              selected: scope,
              onScopeChanged: (newScope) {
                ref
                    .read(leaderboardScopeNotifierProvider.notifier)
                    .setScope(newScope);
              },
            ),
          ),

          // ----------------------------------------------------------------
          // Date range subtitle (week / month scopes only)
          // ----------------------------------------------------------------
          leaderboardAsync.when(
            data: (result) {
              if ((scope == LeaderboardScope.thisWeek ||
                      scope == LeaderboardScope.thisMonth) &&
                  result.weekStart != null &&
                  result.weekEnd != null) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    key: const Key('date_range_subtitle'),
                    '${_formatDate(result.weekStart!)} – ${_formatDate(result.weekEnd!)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // ----------------------------------------------------------------
          // List / loading / error
          // ----------------------------------------------------------------
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
                    ref.invalidate(leaderboardProvider(householdId)),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _LeaderboardBottomNav(
        householdId: householdId,
        currentIndex: _tabIndex,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scope selector
// ---------------------------------------------------------------------------

class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({
    required this.selected,
    required this.onScopeChanged,
  });

  final LeaderboardScope selected;
  final ValueChanged<LeaderboardScope> onScopeChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<LeaderboardScope>(
      key: const Key('scope_selector'),
      segments: LeaderboardScope.values
          .map(
            (s) => ButtonSegment<LeaderboardScope>(
              value: s,
              label: Text(s.label),
            ),
          )
          .toList(),
      selected: {selected},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onScopeChanged(selection.first);
      },
      showSelectedIcon: false,
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
            // Already on leaderboard — no-op.
            break;
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
