import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../providers/household_provider.dart';
import '../widgets/create_household_sheet.dart';
import '../widgets/household_card.dart';

class HouseholdDashboardScreen extends ConsumerWidget {
  const HouseholdDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final householdsAsync = ref.watch(householdsNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Households'),
        actions: [
          // Join by invite link button
          IconButton(
            key: const Key('join_by_invite_button'),
            icon: const Icon(Icons.link_rounded),
            tooltip: 'Join by invite link',
            onPressed: () => _showJoinDialog(context, ref),
          ),
          // Logout button
          IconButton(
            key: const Key('logout_button'),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: () => _logout(ref),
          ),
        ],
      ),
      body: householdsAsync.when(
        loading: () => const LoadingWidget(),
        error: (error, _) => AppErrorWidget(
          message: error.toString(),
          onRetry: () => ref.invalidate(householdsNotifierProvider),
        ),
        data: (households) {
          if (households.isEmpty) {
            return _EmptyState(
              onCreateTap: () => showCreateHouseholdSheet(context),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(householdsNotifierProvider);
              await ref.read(householdsNotifierProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: households.length,
              itemBuilder: (context, index) {
                return HouseholdCard(household: households[index]);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('create_household_fab'),
        onPressed: () => showCreateHouseholdSheet(context),
        tooltip: 'Create household',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _logout(WidgetRef ref) async {
    // logout() must run while the token is still stored: it sends
    // POST /auth/logout (server-side revocation) before clearing storage.
    await ref.read(authNotifierProvider.notifier).logout();
  }

  Future<void> _showJoinDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _JoinHouseholdDialog(parentContext: context),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state widget
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreateTap});

  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.home_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No households yet',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Create a household to start assigning chores.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              key: const Key('empty_state_create_button'),
              onPressed: onCreateTap,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create one'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Join-by-invite dialog — owns its own TextEditingController lifecycle
// ---------------------------------------------------------------------------

class _JoinHouseholdDialog extends ConsumerStatefulWidget {
  const _JoinHouseholdDialog({required this.parentContext});

  final BuildContext parentContext;

  @override
  ConsumerState<_JoinHouseholdDialog> createState() =>
      _JoinHouseholdDialogState();
}

class _JoinHouseholdDialogState extends ConsumerState<_JoinHouseholdDialog> {
  late final TextEditingController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join by Invite Link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Paste the invite link or token below.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('invite_token_field'),
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Invite link or token',
              hintText: 'https://... or token',
              prefixIcon: Icon(Icons.link_rounded),
            ),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('join_household_submit_button'),
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Join'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;

    final token = _extractToken(raw);
    setState(() => _isLoading = true);

    try {
      await ref
          .read(householdsNotifierProvider.notifier)
          .joinByToken(token);

      if (mounted) Navigator.of(context).pop();

      final parent = widget.parentContext;
      if (parent.mounted) {
        ScaffoldMessenger.of(parent).showSnackBar(
          const SnackBar(
            key: Key('join_success_snackbar'),
            content: Text('Successfully joined household!'),
          ),
        );
      }
    } on InviteExpiredException {
      if (mounted) Navigator.of(context).pop();
      final parent = widget.parentContext;
      if (parent.mounted) {
        ScaffoldMessenger.of(parent).showSnackBar(
          SnackBar(
            key: const Key('join_expired_snackbar'),
            content: const Text(
              'Invite link has expired or has already been used.',
            ),
            backgroundColor: Theme.of(parent).colorScheme.error,
          ),
        );
      }
    } on AlreadyMemberException {
      if (mounted) Navigator.of(context).pop();
      final parent = widget.parentContext;
      if (parent.mounted) {
        ScaffoldMessenger.of(parent).showSnackBar(
          SnackBar(
            key: const Key('join_already_member_snackbar'),
            content: const Text(
              'You are already a member of this household.',
            ),
            backgroundColor: Theme.of(parent).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      final parent = widget.parentContext;
      if (parent.mounted) {
        ScaffoldMessenger.of(parent).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(parent).colorScheme.error,
          ),
        );
      }
    }
  }

  String _extractToken(String raw) {
    try {
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        final segments = uri.pathSegments
            .where((s) => s.isNotEmpty && s != 'accept')
            .toList();
        if (segments.isNotEmpty) return segments.last;
      }
    } catch (_) {}
    return raw;
  }
}
