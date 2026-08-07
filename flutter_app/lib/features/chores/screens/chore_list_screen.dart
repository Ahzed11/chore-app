import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dio/dio.dart';

import '../../../core/api/friendly_error.dart';
import '../../../router/app_router.dart';
import '../../../shared/widgets/accessible_tap.dart';
import '../../../shared/widgets/app_bottom_nav_bar.dart';
import '../../../shared/widgets/avatar_colors.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../auth/providers/current_user_provider.dart';
import '../../household/models/member_model.dart';
import '../../household/providers/household_provider.dart';
import '../../household/providers/members_provider.dart';
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
            SnackBar(
              content: Text('Failed to delete: ${friendlyErrorMessage(e)}'),
            ),
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Reassign
  // ---------------------------------------------------------------------------

  Future<void> _reassignChore(ChoreModel chore, String memberId) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(choresNotifierProvider(widget.householdId).notifier)
          .reassignChore(chore.id, memberId);
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Chore reassigned.'),
          backgroundColor: _teal,
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            code == 409
                ? 'This chore can no longer be reassigned.'
                : code == 403
                ? 'You do not have permission to reassign chores.'
                : code == 422
                ? 'That member is no longer part of this household.'
                : 'Failed to reassign chore. Please try again.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to reassign chore. Please try again.'),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final choresAsync = ref.watch(choresNotifierProvider(widget.householdId));
    final household = ref.watch(householdByIdProvider(widget.householdId));
    final membersAsync = ref.watch(membersNotifierProvider(widget.householdId));
    final String householdName = household?.name ?? '';
    final bool isAdmin = ref.watch(isAdminProvider(widget.householdId));

    final List<MemberModel> members = membersAsync.valueOrNull ?? const [];
    final String? currentUserId = ref
        .watch(currentUserProvider)
        .valueOrNull
        ?.id;

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
                pendingCount:
                    choresAsync.whenOrNull(
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
                    error: error,
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
                            choresNotifierProvider(widget.householdId).notifier,
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
                                  members: members,
                                  onDeleteSeries: isAdmin
                                      ? () => _confirmDelete(
                                          context,
                                          chore.definitionId,
                                          chore.title,
                                        )
                                      : null,
                                  onReassign: isAdmin
                                      ? (memberId) =>
                                            _reassignChore(chore, memberId)
                                      : null,
                                  onCompleteTap:
                                      isMyChore && chore.status != 'complete'
                                      ? () => confirmCompleteChore(
                                          context: context,
                                          ref: ref,
                                          householdId: widget.householdId,
                                          chore: chore,
                                        )
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
        bottomNavigationBar: AppBottomNavBar(
          householdId: widget.householdId,
          currentIndex: 0,
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
                label: 'Back to households',
                onTap: () => context.go('/households'),
              ),
              const SizedBox(width: 14),
              if (members.isNotEmpty) _MemberAvatarStack(members: members),
              const Spacer(),
              if (isAdmin)
                _CircleIconButton(
                  icon: Icons.group_rounded,
                  key: const Key('manage_members_button'),
                  label: 'Manage household members',
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
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AccessibleTap(
      onTap: onTap,
      label: label,
      customBorder: const CircleBorder(),
      naturalSize: 40,
      minTapSize: 48,
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
                color: avatarColorForName(shown[i].displayName),
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
  const _Avatar({required this.name, required this.color, required this.size});

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
                child: AccessibleTap(
                  onTap: () => onFilterChanged(key),
                  label: '$label filter',
                  selected: isActive,
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
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
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
                style: const TextStyle(fontSize: 14, color: _secondaryText),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
