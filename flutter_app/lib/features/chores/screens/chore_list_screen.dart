import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dio/dio.dart';

import '../../../router/app_router.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../household/models/member_model.dart';
import '../../household/providers/household_provider.dart';
import '../../household/providers/members_provider.dart';
import '../../leaderboard/providers/leaderboard_provider.dart';
import '../models/chore_model.dart';
import '../providers/chores_provider.dart';
import '../widgets/chore_card.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _teal = Color(0xFF0D9488);
const _darkText = Color(0xFF0F2E2C);
const _secondaryText = Color(0xFF7F9794);
const _tabInactive = Color(0xFF9FB6B3);
const _borderLight = Color(0xFFE6EDEC);
const _filterBorder = Color(0xFFEEF3F2);

const _filterTabs = ['All', 'Pending', 'Overdue', 'Done'];

// ---------------------------------------------------------------------------
// ChoreListScreen
// ---------------------------------------------------------------------------

class ChoreListScreen extends ConsumerStatefulWidget {
  const ChoreListScreen({super.key, required this.householdId});

  final String householdId;

  @override
  ConsumerState<ChoreListScreen> createState() => _ChoreListScreenState();
}

class _ChoreListScreenState extends ConsumerState<ChoreListScreen> {
  String _activeFilter = 'all';

  // ---------------------------------------------------------------------------
  // Filter logic
  // ---------------------------------------------------------------------------

  List<ChoreModel> _applyFilter(List<ChoreModel> chores) {
    return chores.where((c) {
      if (c.status == 'cancelled') return false;
      switch (_activeFilter) {
        case 'pending':
          return c.status == 'pending' && !c.isOverdue;
        case 'overdue':
          return c.isOverdue;
        case 'done':
          return c.status == 'complete';
        default:
          return true;
      }
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Delete confirmation dialog
  // ---------------------------------------------------------------------------

  Future<void> _confirmDelete(
    BuildContext context,
    String definitionId,
    String title,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete series?'),
        content: Text(
          'This will soft-delete the entire "$title" series. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      try {
        await ref
            .read(choresNotifierProvider(widget.householdId).notifier)
            .deleteChore(definitionId);
      } catch (e) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Complete confirmation
  // ---------------------------------------------------------------------------

  Future<void> _confirmComplete(ChoreModel chore) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final confirmed = await showChoreCompleteSheet(context, chore);
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(choresNotifierProvider(widget.householdId).notifier)
          .completeChore(chore.id);
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('You earned ${chore.pointValue} points!'),
          backgroundColor: _teal,
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(code == 409
            ? 'This chore was already completed.'
            : code == 403
                ? 'You are not assigned to this chore.'
                : 'Failed to complete chore. Please try again.'),
      ));
    } catch (_) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Failed to complete chore. Please try again.')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final choresAsync = ref.watch(choresNotifierProvider(widget.householdId));
    final householdsAsync = ref.watch(householdsNotifierProvider);
    final membersAsync = ref.watch(membersNotifierProvider(widget.householdId));
    final String householdName = householdsAsync.whenOrNull(
          data: (list) => list
              .where((h) => h.id == widget.householdId)
              .firstOrNull
              ?.name,
        ) ??
        '';

    final bool isAdmin = householdsAsync.whenOrNull(
          data: (list) => list
              .where((h) => h.id == widget.householdId)
              .firstOrNull
              ?.isAdmin,
        ) ??
        false;

    final List<MemberModel> members =
        membersAsync.valueOrNull ?? const [];
    final String? currentUserId = ref.watch(currentUserIdProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/households');
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _ChoreListHeader(
                householdId: widget.householdId,
                householdName: householdName,
                isAdmin: isAdmin,
                members: members,
                pendingCount: choresAsync.whenOrNull(
                      data: (list) => list
                          .where(
                            (c) =>
                                c.status != 'cancelled' &&
                                c.status != 'complete',
                          )
                          .length,
                    ) ??
                    0,
              ),

              // Filter tabs
              _ChoreFilterTabs(
                activeFilter: _activeFilter,
                onFilterChanged: (f) => setState(() => _activeFilter = f),
              ),

              // Chore list
              Expanded(
                child: choresAsync.when(
                  loading: () =>
                      const LoadingWidget(message: 'Loading chores...'),
                  error: (error, _) => AppErrorWidget(
                    message: error.toString(),
                    onRetry: () => ref
                        .read(
                          choresNotifierProvider(widget.householdId).notifier,
                        )
                        .refresh(),
                  ),
                  data: (chores) {
                    final filtered = _applyFilter(chores);
                    return RefreshIndicator(
                      color: _teal,
                      onRefresh: () => ref
                          .read(
                            choresNotifierProvider(widget.householdId)
                                .notifier,
                          )
                          .refresh(),
                      child: filtered.isEmpty
                          ? _EmptyState(filter: _activeFilter)
                          : ListView.builder(
                              key: const Key('chore_list'),
                              padding: const EdgeInsets.only(
                                top: 8,
                                bottom: 100,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final chore = filtered[index];
                                final isMyChore =
                                    currentUserId != null &&
                                    chore.assigneeId == currentUserId;
                                return ChoreCard(
                                  key: Key('chore_card_${chore.id}'),
                                  chore: chore,
                                  isAdmin: isAdmin,
                                  onDeleteSeries: isAdmin
                                      ? () => _confirmDelete(
                                            context,
                                            chore.definitionId,
                                            chore.title,
                                          )
                                      : null,
                                  onCompleteTap: isMyChore &&
                                          chore.status != 'complete'
                                      ? () => _confirmComplete(chore)
                                      : null,
                                );
                              },
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: isAdmin
            ? FloatingActionButton(
                key: const Key('add_chore_fab'),
                onPressed: () => context.pushNamed(
                  AppRoutes.createChore,
                  pathParameters: {'householdId': widget.householdId},
                ),
                tooltip: 'Add chore',
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                elevation: 4,
                child: const Icon(Icons.add_rounded),
              )
            : null,
        bottomNavigationBar: _ChoreListBottomNav(
          householdId: widget.householdId,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _ChoreListHeader extends StatelessWidget {
  const _ChoreListHeader({
    required this.householdId,
    required this.householdName,
    required this.isAdmin,
    required this.members,
    required this.pendingCount,
  });

  final String householdId;
  final String householdName;
  final bool isAdmin;
  final List<MemberModel> members;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action row
          Row(
            children: [
              _CircleIconButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => context.go('/households'),
              ),
              const SizedBox(width: 14),
              if (members.isNotEmpty)
                _MemberAvatarStack(members: members),
              const Spacer(),
              if (isAdmin)
                _CircleIconButton(
                  icon: Icons.group_rounded,
                  key: const Key('manage_members_button'),
                  onTap: () => context.pushNamed(
                    AppRoutes.householdManage,
                    pathParameters: {'householdId': householdId},
                  ),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // Household name
          Text(
            householdName,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: _darkText,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 4),

          // Subtitle
          Text(
            pendingCount == 0
                ? 'All caught up!'
                : '$pendingCount chore${pendingCount == 1 ? '' : 's'} remaining',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _secondaryText,
            ),
          ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Circle icon button
// ---------------------------------------------------------------------------

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: _borderLight),
        ),
        child: Icon(icon, size: 20, color: _darkText),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stacked member avatars
// ---------------------------------------------------------------------------

class _MemberAvatarStack extends StatelessWidget {
  const _MemberAvatarStack({required this.members});

  final List<MemberModel> members;

  static const List<Color> _colors = [
    Color(0xFF14B8A6),
    Color(0xFF0EA5E9),
    Color(0xFF8B5CF6),
    Color(0xFF22C55E),
    Color(0xFFF472B6),
    Color(0xFFF97316),
  ];

  static Color _colorFor(String name) {
    if (name.isEmpty) return _colors[0];
    return _colors[name.codeUnitAt(0) % _colors.length];
  }

  @override
  Widget build(BuildContext context) {
    const avatarSize = 30.0;
    const step = 21.0;
    const maxAvatars = 3;

    final shown = members.take(maxAvatars).toList();
    final overflow = members.length - shown.length;
    final itemCount = shown.length + (overflow > 0 ? 1 : 0);
    final totalWidth = avatarSize + (itemCount - 1) * step;

    return SizedBox(
      width: totalWidth,
      height: avatarSize,
      child: Stack(
        children: [
          for (int i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: _Avatar(
                name: shown[i].displayName,
                color: _colorFor(shown[i].displayName),
                size: avatarSize,
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: shown.length * step,
              child: Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF1F5F5),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+$overflow',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _teal,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.color,
    required this.size,
  });

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter tabs
// ---------------------------------------------------------------------------

class _ChoreFilterTabs extends StatelessWidget {
  const _ChoreFilterTabs({
    required this.activeFilter,
    required this.onFilterChanged,
  });

  final String activeFilter;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: _filterTabs.map((label) {
              final key = label.toLowerCase();
              final isActive = activeFilter == key;
              return Padding(
                padding: const EdgeInsets.only(right: 26),
                child: GestureDetector(
                  onTap: () => onFilterChanged(key),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isActive ? _teal : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? _teal : _tabInactive,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 1, color: _filterBorder),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom navigation bar
// ---------------------------------------------------------------------------

class _ChoreListBottomNav extends StatelessWidget {
  const _ChoreListBottomNav({required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      key: const Key('bottom_nav_bar'),
      currentIndex: 0,
      onTap: (index) {
        switch (index) {
          case 1:
            context.goNamed(
              AppRoutes.myChores,
              pathParameters: {'householdId': householdId},
            );
          case 2:
            context.goNamed(
              AppRoutes.leaderboard,
              pathParameters: {'householdId': householdId},
            );
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.format_list_bulleted_rounded),
          label: 'All Chores',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_rounded),
          label: 'My Chores',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.emoji_events_rounded),
          label: 'Leaderboard',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final String filter;

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = switch (filter) {
      'done' => (
          Icons.check_circle_outline_rounded,
          'No completed chores',
          'Completed chores will appear here.',
        ),
      'overdue' => (
          Icons.schedule_rounded,
          'No overdue chores',
          'Great work keeping up!',
        ),
      'pending' => (
          Icons.checklist_rounded,
          'Nothing pending',
          'All current chores are either done or overdue.',
        ),
      _ => (
          Icons.check_circle_outline_rounded,
          'All clear!',
          'No chores here. Add one with the + button.',
        ),
    };

    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                key: const Key('empty_state_icon'),
                size: 72,
                color: _teal.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _darkText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: _secondaryText,
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
