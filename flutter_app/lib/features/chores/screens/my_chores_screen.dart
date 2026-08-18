import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../../shared/widgets/accessible_tap.dart';
import '../../../shared/widgets/app_bottom_nav_bar.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../auth/providers/current_user_provider.dart';
import '../../household/providers/household_provider.dart';
import '../../leaderboard/providers/leaderboard_provider.dart';
import '../models/chore_model.dart';
import '../providers/chores_provider.dart';
import '../widgets/chore_card.dart';

const _teal = Color(0xFF0D9488);
const _darkText = Color(0xFF0F2E2C);
const _secondaryText = Color(0xFF7F9794);
const _mutedText = Color(0xFF9FB6B3);
const _inactiveTab = Color(0xFFA8BCB9);
const _borderLight = Color(0xFFE6EDEC);
const _filterBorder = Color(0xFFEEF3F2);

// ---------------------------------------------------------------------------
// MyChoresScreen
// ---------------------------------------------------------------------------

class MyChoresScreen extends ConsumerStatefulWidget {
  const MyChoresScreen({super.key, required this.householdId});

  final String householdId;

  @override
  ConsumerState<MyChoresScreen> createState() => _MyChoresScreenState();
}

class _MyChoresScreenState extends ConsumerState<MyChoresScreen> {
  String _activeTab = 'todo';

  @override
  Widget build(BuildContext context) {
    final choresAsync = ref.watch(choresNotifierProvider(widget.householdId));
    final currentUserAsync = ref.watch(currentUserProvider);
    final weeklyAsync = ref.watch(
      weeklyLeaderboardProvider(widget.householdId),
    );

    final String? userId = currentUserAsync.whenOrNull(data: (u) => u.id);
    final String displayName =
        currentUserAsync.whenOrNull(data: (u) => u.displayName) ?? '';
    final firstName = displayName.split(' ').first;

    final bool isAdmin = ref.watch(isAdminProvider(widget.householdId));

    // Rank from leaderboard API (requires knowing other users' scores)
    int? rank;
    weeklyAsync.whenData((result) {
      rank = result.requestingUserRank;
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/households');
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: choresAsync.when(
            loading: () => const LoadingWidget(message: 'Loading your chores…'),
            error: (error, _) => AppErrorWidget(
              error: error,
              onRetry: () => ref
                  .read(choresNotifierProvider(widget.householdId).notifier)
                  .refresh(),
            ),
            data: (allChores) {
              final myChores = userId == null
                  ? <ChoreModel>[]
                  : allChores
                        .where(
                          (c) =>
                              c.assigneeId == userId &&
                              c.status != 'cancelled',
                        )
                        .toList();

              final overdue = myChores.where((c) => c.isOverdue).toList()
                ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
              final pending =
                  myChores
                      .where((c) => c.status == 'pending' && !c.isOverdue)
                      .toList()
                    // TASK-111: newest-created first (overdue block above
                    // stays urgency-pinned by due date). id breaks created_at
                    // ties the same way the server does (scheduler-created
                    // recurring instances share one transaction timestamp).
                    ..sort((a, b) {
                      final byCreated = b.createdAt.compareTo(a.createdAt);
                      return byCreated != 0
                          ? byCreated
                          : b.id.compareTo(a.id);
                    });
              final todo = [...overdue, ...pending];
              final done =
                  myChores
                      .where(
                        (c) =>
                            c.status == 'complete' ||
                            c.status == 'dismissed',
                      )
                      .toList()
                    ..sort(
                      (a, b) => (b.completedAt ?? b.dueDate).compareTo(
                        a.completedAt ?? a.dueDate,
                      ),
                    );

              final viewList = _activeTab == 'todo' ? todo : done;

              // Compute weekly points from chores completed since Monday.
              final weekStart = () {
                final now = DateTime.now();
                return DateTime(
                  now.year,
                  now.month,
                  now.day - (now.weekday - 1),
                );
              }();
              final weeklyPoints = done
                  .where(
                    (c) =>
                        c.completedAt != null &&
                        !c.completedAt!.isBefore(weekStart),
                  )
                  .fold(
                    0,
                    // Dismissed chores are closed with zero points — they must
                    // never count toward the weekly total (TASK-104).
                    (sum, c) =>
                        sum +
                        (c.status == 'dismissed'
                            ? 0
                            : (c.pointsAwarded ?? c.pointValue)),
                  );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  _MyChoresHeader(
                    firstName: firstName,
                    isAdmin: isAdmin,
                    householdId: widget.householdId,
                  ),

                  // Points banner
                  _WeeklyPointsBanner(weeklyPoints: weeklyPoints, rank: rank),

                  // Tab bar
                  _MyChoreTabBar(
                    activeTab: _activeTab,
                    todoCount: todo.length,
                    doneCount: done.length,
                    onTabChanged: (t) => setState(() => _activeTab = t),
                  ),

                  const Divider(height: 1, color: _filterBorder),

                  // Chore list
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: RefreshIndicator(
                        key: ValueKey(_activeTab),
                        color: _teal,
                        onRefresh: () async {
                          await ref
                              .read(
                                choresNotifierProvider(
                                  widget.householdId,
                                ).notifier,
                              )
                              .refresh();
                          ref.invalidate(
                            weeklyLeaderboardProvider(widget.householdId),
                          );
                        },
                        child: _activeTab == 'todo' && todo.isEmpty
                            ? _AllCaughtUpState()
                            : _activeTab == 'done' && done.isEmpty
                            ? const _NothingDoneState()
                            : ListView.builder(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 100,
                                ),
                                itemCount: viewList.length,
                                itemBuilder: (context, index) {
                                  final chore = viewList[index];
                                  return ChoreCard(
                                    key: Key('my_chore_card_${chore.id}'),
                                    chore: chore,
                                    showAssignee: false,
                                    onCompleteTap:
                                        chore.status != 'complete' &&
                                            chore.status != 'dismissed'
                                        ? () => confirmCompleteChore(
                                            context: context,
                                            ref: ref,
                                            householdId: widget.householdId,
                                            chore: chore,
                                          )
                                        : null,
                                    // Every chore here is the current user's
                                    // own — dismiss is always available while
                                    // actionable (TASK-104).
                                    onDismiss:
                                        chore.status == 'pending' ||
                                            chore.status == 'overdue'
                                        ? () => confirmDismissChore(
                                            context: context,
                                            ref: ref,
                                            householdId: widget.householdId,
                                            chore: chore,
                                          )
                                        : null,
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: AppBottomNavBar(
          householdId: widget.householdId,
          currentIndex: 1,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _MyChoresHeader extends StatelessWidget {
  const _MyChoresHeader({
    required this.firstName,
    required this.isAdmin,
    required this.householdId,
  });

  final String firstName;
  final bool isAdmin;
  final String householdId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hey ${firstName.isNotEmpty ? firstName : 'there'} 👋',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _secondaryText,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'My Chores',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: _darkText,
                    letterSpacing: -0.02 * 30,
                  ),
                ),
              ],
            ),
          ),
          if (isAdmin)
            AccessibleTap(
              onTap: () => context.pushNamed(
                AppRoutes.householdManage,
                pathParameters: {'householdId': householdId},
              ),
              label: 'Manage household members',
              customBorder: const CircleBorder(),
              naturalSize: 40,
              minTapSize: 48,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _borderLight),
                  color: Colors.white,
                ),
                child: const Icon(
                  Icons.group_rounded,
                  size: 20,
                  color: _darkText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weekly points / progress banner
// ---------------------------------------------------------------------------

class _WeeklyPointsBanner extends StatelessWidget {
  const _WeeklyPointsBanner({required this.weeklyPoints, this.rank});

  final int weeklyPoints;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('points_banner'),
      margin: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _teal,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _teal.withValues(alpha: 0.45),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Star icon box
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFFBBF24),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              // Points text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your points this week',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    Text(
                      '$weeklyPoints pts',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // Rank pill
              if (rank != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_events_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Rank #$rank',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab bar (To Do / Done) — underline style
// ---------------------------------------------------------------------------

class _MyChoreTabBar extends StatelessWidget {
  const _MyChoreTabBar({
    required this.activeTab,
    required this.todoCount,
    required this.doneCount,
    required this.onTabChanged,
  });

  final String activeTab;
  final int todoCount;
  final int doneCount;
  final void Function(String) onTabChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Row(
        children: [
          _TabButton(
            label: 'To Do',
            icon: Icons.checklist_rounded,
            count: todoCount,
            isActive: activeTab == 'todo',
            onTap: () => onTabChanged('todo'),
          ),
          const SizedBox(width: 28),
          _TabButton(
            label: 'Done',
            icon: Icons.check_circle_rounded,
            count: doneCount,
            isActive: activeTab == 'done',
            onTap: () => onTabChanged('done'),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? _teal : _inactiveTab;
    final badgeBg = isActive
        ? const Color(0xFFD8F0EC)
        : const Color(0xFFF1F6F5);
    final badgeText = isActive ? _teal : _inactiveTab;

    return AccessibleTap(
      onTap: onTap,
      label: '$label ($count)',
      selected: isActive,
      child: Container(
        padding: const EdgeInsets.only(bottom: 11),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? _teal : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: badgeText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty states
// ---------------------------------------------------------------------------

class _AllCaughtUpState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('todo_empty_state'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 54),
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAFAF7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  size: 44,
                  color: _teal,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'All caught up! 🎉',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: _darkText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'No chores left for you.\nEnjoy your well-deserved break.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _secondaryText,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NothingDoneState extends StatelessWidget {
  const _NothingDoneState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('done_empty_state'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 54),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F6F5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 34,
                  color: Color(0xFFB3C6C3),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nothing done yet',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: _darkText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'Complete a chore to see it here.',
                style: TextStyle(fontSize: 14, color: _mutedText),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Complete confirmation bottom sheet
// ---------------------------------------------------------------------------
