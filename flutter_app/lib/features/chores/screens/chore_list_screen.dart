import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../auth/providers/current_user_provider.dart';
import '../../household/providers/household_provider.dart';
import '../models/chore_model.dart';
import '../providers/chores_provider.dart';
import '../widgets/chore_card.dart';

// ---------------------------------------------------------------------------
// Status / category filter options
// ---------------------------------------------------------------------------

const _statusOptions = ['All', 'Pending', 'Overdue', 'Complete'];

const _categoryOptions = <String, String>{
  'All': 'All',
  'kitchen': 'Kitchen',
  'bathroom': 'Bathroom',
  'bedroom': 'Bedroom',
  'living_room': 'Living Room',
  'laundry_room': 'Laundry',
  'garden_outdoor': 'Garden',
  'garage': 'Garage',
  'other_general': 'Other',
};

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
  // ---------------------------------------------------------------------------
  // Bottom nav index (0 = All Chores, 1 = My Chores, 2 = Leaderboard)
  // ---------------------------------------------------------------------------

  int _bottomNavIndex = 0;

  void _onBottomNavTap(int index) {
    if (index == _bottomNavIndex) return;
    setState(() => _bottomNavIndex = index);

    if (index == 1) {
      context.goNamed(
        'my-chores',
        pathParameters: {'householdId': widget.householdId},
      );
    } else if (index == 2) {
      context.goNamed(
        'leaderboard',
        pathParameters: {'householdId': widget.householdId},
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(choreFilterNotifierProvider);
    final choresAsync =
        ref.watch(choresNotifierProvider(widget.householdId));
    final householdsAsync = ref.watch(householdsNotifierProvider);
    final currentUserAsync = ref.watch(currentUserProvider);

    // Derive household name and admin status from the households list.
    final String householdName = householdsAsync.whenOrNull(
          data: (list) => list
              .where((h) => h.id == widget.householdId)
              .firstOrNull
              ?.name,
        ) ??
        'Chores';

    final bool isAdmin = householdsAsync.whenOrNull(
          data: (list) => list
              .where((h) => h.id == widget.householdId)
              .firstOrNull
              ?.isAdmin,
        ) ??
        false;

    final String? currentUserId = currentUserAsync.whenOrNull(
      data: (u) => u.id,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(householdName),
        leading: BackButton(
          onPressed: () => context.go('/households'),
        ),
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              key: const Key('add_chore_fab'),
              onPressed: () => context.goNamed(
                'create-chore',
                pathParameters: {'householdId': widget.householdId},
              ),
              tooltip: 'Add chore',
              child: const Icon(Icons.add_task),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: _onBottomNavTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'All Chores',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'My Chores',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: 'Leaderboard',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          _FilterBar(
            filter: filter,
            currentUserId: currentUserId,
            onStatusChanged: (s) =>
                ref.read(choreFilterNotifierProvider.notifier).setStatus(s),
            onCategoryChanged: (c) =>
                ref.read(choreFilterNotifierProvider.notifier).setCategory(c),
            onMyChoresToggled: () {
              if (currentUserId != null) {
                ref
                    .read(choreFilterNotifierProvider.notifier)
                    .toggleMyChoresOnly(currentUserId);
              }
            },
          ),
          // Chore list
          Expanded(
            child: choresAsync.when(
              loading: () => const LoadingWidget(message: 'Loading chores...'),
              error: (error, _) => AppErrorWidget(
                message: error.toString(),
                onRetry: () => ref
                    .read(choresNotifierProvider(widget.householdId).notifier)
                    .refresh(),
              ),
              data: (chores) {
                final filtered = _applyFilter(chores, filter);
                return RefreshIndicator(
                  onRefresh: () => ref
                      .read(
                          choresNotifierProvider(widget.householdId).notifier)
                      .refresh(),
                  child: filtered.isEmpty
                      ? _EmptyState()
                      : ListView.builder(
                          key: const Key('chore_list'),
                          padding: const EdgeInsets.only(bottom: 80, top: 4),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final chore = filtered[index];
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
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Client-side filter
  // ---------------------------------------------------------------------------

  List<ChoreModel> _applyFilter(
      List<ChoreModel> chores, ChoreFilter filter) {
    return chores.where((c) {
      if (c.status == 'cancelled') return false;
      if (filter.status != null && filter.status!.isNotEmpty) {
        if (c.status != filter.status) return false;
      }
      if (filter.category != null && filter.category!.isNotEmpty) {
        if (c.category != filter.category) return false;
      }
      if (filter.assigneeId != null && filter.assigneeId!.isNotEmpty) {
        if (c.assigneeId != filter.assigneeId) return false;
      }
      return true;
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
          'This will soft-delete the entire "$title" series for this household. This cannot be undone.',
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
}

// ---------------------------------------------------------------------------
// Filter bar widget
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.currentUserId,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onMyChoresToggled,
  });

  final ChoreFilter filter;
  final String? currentUserId;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onMyChoresToggled;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        key: const Key('filter_bar'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Status chips
            ..._statusOptions.map((label) {
              final value =
                  label == 'All' ? null : label.toLowerCase();
              final selected = filter.status == value;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  key: Key('status_chip_$label'),
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => onStatusChanged(value),
                ),
              );
            }),
            const SizedBox(width: 4),
            // Category chips
            ..._categoryOptions.entries.map((entry) {
              final value = entry.key == 'All' ? null : entry.key;
              final selected = filter.category == value;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  key: Key('category_chip_${entry.key}'),
                  label: Text(entry.value),
                  selected: selected,
                  onSelected: (_) => onCategoryChanged(value),
                ),
              );
            }),
            const SizedBox(width: 4),
            // "My chores" toggle
            FilterChip(
              key: const Key('my_chores_chip'),
              label: const Text('My Chores'),
              avatar: const Icon(Icons.person, size: 16),
              selected:
                  currentUserId != null &&
                  filter.assigneeId == currentUserId,
              onSelected: (_) => onMyChoresToggled(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state widget
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      // Wrapped in ListView so RefreshIndicator still works on empty state.
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline,
                key: const Key('empty_state_icon'),
                size: 72,
                color: theme.colorScheme.primary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                'No chores found',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your filters or add a new chore.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade500,
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
