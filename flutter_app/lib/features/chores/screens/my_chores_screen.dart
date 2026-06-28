import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../auth/providers/current_user_provider.dart';
import '../models/chore_model.dart';
import '../providers/chores_provider.dart';

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
  static const int _tabIndex = 1;

  @override
  Widget build(BuildContext context) {
    final choresAsync = ref.watch(choresNotifierProvider(widget.householdId));
    final currentUserAsync = ref.watch(currentUserProvider);

    final String? currentUserId = currentUserAsync.whenOrNull(
      data: (u) => u.id,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('My Chores')),
      bottomNavigationBar: _MyChoresBottomNav(
        householdId: widget.householdId,
        currentIndex: _tabIndex,
      ),
      body: choresAsync.when(
        loading: () => const LoadingWidget(message: 'Loading your chores...'),
        error: (error, _) => AppErrorWidget(
          message: error.toString(),
          onRetry: () => ref
              .read(choresNotifierProvider(widget.householdId).notifier)
              .refresh(),
        ),
        data: (allChores) {
          // Filter to current user's assigned chores only.
          final myChores = currentUserId == null
              ? <ChoreModel>[]
              : allChores
                  .where((c) => c.assigneeId == currentUserId)
                  .toList();

          final sorted = _sortChores(myChores);

          // Compute all-time points from completed chores (client-side).
          final totalPoints = myChores
              .where((c) => c.status == 'complete')
              .fold<int>(0, (sum, c) => sum + (c.pointsAwarded ?? 0));

          return RefreshIndicator(
            onRefresh: () => ref
                .read(choresNotifierProvider(widget.householdId).notifier)
                .refresh(),
            child: CustomScrollView(
              slivers: [
                // Points banner always visible at the top.
                SliverToBoxAdapter(
                  child: _PointsBanner(points: totalPoints),
                ),

                if (sorted.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        key: Key('empty_state_my_chores'),
                        'No chores assigned to you yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 80, top: 4),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final chore = sorted[index];
                          final isActionable = chore.status == 'pending' ||
                              chore.status == 'overdue';
                          return _MyChoreCard(
                            key: Key('my_chore_card_${chore.id}'),
                            chore: chore,
                            onMarkDone: isActionable
                                ? () => _confirmComplete(context, chore)
                                : null,
                          );
                        },
                        childCount: sorted.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sort: overdue (due_date ASC) → pending (due_date ASC) → complete
  //       (completedAt DESC) → others
  // ---------------------------------------------------------------------------

  List<ChoreModel> _sortChores(List<ChoreModel> chores) {
    final overdue = chores.where((c) => c.isOverdue).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final pending = chores
        .where((c) => c.status == 'pending' && !c.isOverdue)
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final complete = chores.where((c) => c.status == 'complete').toList()
      ..sort((a, b) => (b.completedAt ?? b.dueDate)
          .compareTo(a.completedAt ?? a.dueDate));

    final others = chores
        .where((c) =>
            !c.isOverdue &&
            c.status != 'pending' &&
            c.status != 'complete')
        .toList();

    return [...overdue, ...pending, ...complete, ...others];
  }

  // ---------------------------------------------------------------------------
  // Mark-as-done confirmation flow
  // ---------------------------------------------------------------------------

  Future<void> _confirmComplete(
    BuildContext context,
    ChoreModel chore,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CompleteConfirmSheet(chore: chore),
    );

    if (confirmed != true || !mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(choresNotifierProvider(widget.householdId).notifier)
          .completeChore(chore.id);

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('You earned ${chore.pointValue} points!'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final statusCode = e.response?.statusCode;
      final message = statusCode == 409
          ? 'This chore was already completed.'
          : statusCode == 403
              ? 'You are not assigned to this chore.'
              : 'Failed to complete chore. Please try again.';
      scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to complete chore. Please try again.'),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Points banner
// ---------------------------------------------------------------------------

class _PointsBanner extends StatelessWidget {
  const _PointsBanner({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('points_banner'),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: Colors.amber, size: 36),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Total Points',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$points pts',
                key: const Key('points_value'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
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
// My chore card — extends the standard ChoreCard layout with a
// "Mark as done" action and completion details row.
// ---------------------------------------------------------------------------

class _MyChoreCard extends StatelessWidget {
  const _MyChoreCard({
    super.key,
    required this.chore,
    this.onMarkDone,
  });

  final ChoreModel chore;

  /// Non-null only for pending / overdue chores.
  final VoidCallback? onMarkDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = chore.statusColor;
    final catIcon =
        categoryIcons[chore.category] ?? Icons.home_repair_service;
    final catLabel = categoryLabels[chore.category] ?? chore.category;
    final dueDateStr = _formatDate(chore.dueDate);
    final effortLabel =
        '${_capitalize(chore.effortLevel)} ${chore.pointValue}pts';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status colour stripe
            Container(
              width: 5,
              decoration: BoxDecoration(color: statusColor),
            ),
            // Card body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---- category + effort chip ----
                    Row(
                      children: [
                        Icon(catIcon,
                            size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          catLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Chip(
                          key: Key('effort_chip_${chore.id}'),
                          label: Text(effortLabel),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          labelStyle: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          backgroundColor: _effortChipColor(chore.effortLevel),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // ---- title ----
                    Text(
                      chore.title,
                      key: Key('my_chore_title_${chore.id}'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ---- due date row ----
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: chore.isOverdue
                              ? Colors.red
                              : theme.colorScheme.onSurface,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dueDateStr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: chore.isOverdue ? Colors.red : null,
                            fontWeight: chore.isOverdue
                                ? FontWeight.w700
                                : null,
                          ),
                        ),
                        if (chore.isOverdue) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: Colors.red,
                          ),
                        ],
                      ],
                    ),

                    // ---- completion details (complete chores only) ----
                    if (chore.status == 'complete') ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: Color(0xFF4CAF50),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              key: Key('completion_info_${chore.id}'),
                              'Completed on ${_formatDate(chore.completedAt ?? chore.dueDate)}'
                              ' • ${chore.pointsAwarded ?? chore.pointValue} pts',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF4CAF50),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // ---- "Mark as done" button (pending / overdue only) ----
                    if (onMarkDone != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: Key('mark_done_button_${chore.id}'),
                          onPressed: onMarkDone,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Mark as done'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers (mirrors ChoreCard helpers to avoid cross-file import)
  // ---------------------------------------------------------------------------

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  Color _effortChipColor(String effortLevel) {
    switch (effortLevel) {
      case 'hard':
        return const Color(0xFFFFCDD2); // light red
      case 'medium':
        return const Color(0xFFFFF9C4); // light yellow
      case 'easy':
      default:
        return const Color(0xFFC8E6C9); // light green
    }
  }
}

// ---------------------------------------------------------------------------
// Complete confirmation bottom sheet
// ---------------------------------------------------------------------------

class _CompleteConfirmSheet extends StatelessWidget {
  const _CompleteConfirmSheet({required this.chore});

  final ChoreModel chore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text(
              'Complete chore?',
              key: const Key('complete_sheet_title'),
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),

            Text(
              chore.title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Effort: ${_capitalize(chore.effortLevel)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),

            // Points reward callout
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFC8E6C9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded,
                      color: Colors.amber, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Complete this task and earn ${chore.pointValue} points!',
                      key: const Key('confirm_points_text'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('confirm_cancel_button'),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('confirm_done_button'),
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Complete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ---------------------------------------------------------------------------
// Bottom navigation bar (My Chores = index 1)
// ---------------------------------------------------------------------------

class _MyChoresBottomNav extends StatelessWidget {
  const _MyChoresBottomNav({
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
            break; // Already on My Chores.
          case 2:
            context.goNamed(
              AppRoutes.leaderboard,
              pathParameters: {'householdId': householdId},
            );
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
