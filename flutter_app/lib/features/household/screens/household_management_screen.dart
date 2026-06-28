import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../leaderboard/providers/leaderboard_provider.dart';
import '../providers/household_provider.dart';
import '../providers/members_provider.dart';
import '../widgets/member_tile.dart';

class HouseholdManagementScreen extends ConsumerStatefulWidget {
  const HouseholdManagementScreen({super.key, required this.householdId});

  final String householdId;

  @override
  ConsumerState<HouseholdManagementScreen> createState() =>
      _HouseholdManagementScreenState();
}

class _HouseholdManagementScreenState
    extends ConsumerState<HouseholdManagementScreen> {
  // -------------------------------------------------------------------------
  // Household name edit dialog
  // -------------------------------------------------------------------------

  Future<void> _showEditNameDialog(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('edit_name_dialog'),
        title: const Text('Edit household name'),
        content: TextField(
          key: const Key('edit_name_field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Household name',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            key: const Key('edit_name_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('edit_name_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // Capture name BEFORE disposing the controller.
    final newName = controller.text.trim();
    controller.dispose();

    if (confirmed != true) return;
    if (!mounted) return;
    if (newName.isEmpty || newName == currentName) return;

    // Capture context-dependent references before any further await.
    // ignore: use_build_context_synchronously
    final messenger = ScaffoldMessenger.of(context);
    // ignore: use_build_context_synchronously
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      await ref
          .read(householdsNotifierProvider.notifier)
          .updateHouseholdName(widget.householdId, newName);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to update name: $e'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Invite
  // -------------------------------------------------------------------------

  Future<void> _generateInvite() async {
    // Capture context-dependent references before the await.
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final router = GoRouter.of(context);
    final dio = ref.read(dioProvider);

    try {
      final response = await dio.post<Map<String, dynamic>>(
        ApiEndpoints.householdInvites(widget.householdId),
      );
      if (!mounted) return;
      router.goNamed(
        'invite',
        pathParameters: {'householdId': widget.householdId},
        extra: response.data,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to generate invite: $e'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Leave household
  // -------------------------------------------------------------------------

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('leave_dialog'),
        title: const Text('Leave household'),
        content: const Text(
          'Are you sure you want to leave this household? '
          'You will lose access to all its chores.',
        ),
        actions: [
          TextButton(
            key: const Key('leave_cancel_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('leave_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Capture context-dependent references before any further await.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      await ref
          .read(householdsNotifierProvider.notifier)
          .leaveHousehold(widget.householdId);
      if (!mounted) return;
      router.go('/households');
    } on SoleAdminException {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('sole_admin_error_dialog'),
          title: const Text('Cannot leave'),
          content: const Text(
            'You are the sole admin. Promote another member first.',
          ),
          actions: [
            TextButton(
              key: const Key('sole_admin_error_ok'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to leave household: $e'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final householdsAsync = ref.watch(householdsNotifierProvider);
    final membersAsync =
        ref.watch(membersNotifierProvider(widget.householdId));
    final currentUserId = ref.watch(currentUserIdProvider);

    // Retrieve the current household from the list provider.
    final household = householdsAsync.valueOrNull
        ?.where((h) => h.id == widget.householdId)
        .firstOrNull;

    final householdName = household?.name ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Household')),
      body: CustomScrollView(
        slivers: [
          // ------------------------------------------------------------------
          // Section 1 — Household info
          // ------------------------------------------------------------------
          const SliverToBoxAdapter(
            child: _SectionHeader(title: 'Household Info'),
          ),
          SliverToBoxAdapter(
            child: Card(
              margin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                key: const Key('household_name_tile'),
                leading: const Icon(Icons.home_rounded),
                title: householdsAsync.isLoading
                    ? const Text('Loading…')
                    : Text(
                        householdName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                subtitle: const Text('Tap to rename'),
                trailing: const Icon(Icons.edit_rounded),
                onTap: householdsAsync.isLoading
                    ? null
                    : () => _showEditNameDialog(householdName),
              ),
            ),
          ),

          // ------------------------------------------------------------------
          // Section 2 — Members
          // ------------------------------------------------------------------
          const SliverToBoxAdapter(
            child: _SectionHeader(title: 'Members'),
          ),
          membersAsync.when(
            loading: () =>
                const SliverToBoxAdapter(child: LoadingWidget()),
            error: (error, _) => SliverToBoxAdapter(
              child: AppErrorWidget(
                message: error.toString(),
                onRetry: () => ref.invalidate(
                  membersNotifierProvider(widget.householdId),
                ),
              ),
            ),
            data: (members) => SliverList.builder(
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                return MemberTile(
                  key: Key('member_tile_${member.userId}'),
                  member: member,
                  householdId: widget.householdId,
                  currentUserId: currentUserId,
                );
              },
            ),
          ),

          // ------------------------------------------------------------------
          // Section 3 — Invite
          // ------------------------------------------------------------------
          const SliverToBoxAdapter(
            child: _SectionHeader(title: 'Invite'),
          ),
          SliverToBoxAdapter(
            child: Card(
              margin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                key: const Key('invite_tile'),
                leading: const Icon(Icons.person_add_rounded),
                title: const Text('Invite member'),
                subtitle: const Text('Generate an invite link'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _generateInvite,
              ),
            ),
          ),

          // ------------------------------------------------------------------
          // Section 4 — Danger zone
          // ------------------------------------------------------------------
          const SliverToBoxAdapter(
            child: _SectionHeader(title: 'Danger Zone'),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.error,
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Leaving removes your access to all chores and '
                        'data in this household.',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('leave_household_button'),
                        onPressed: _confirmLeave,
                        style: TextButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('Leave household'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
