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
    await AuthStorage.clearToken();
    await ref.read(authNotifierProvider.notifier).logout();
  }

  Future<void> _showJoinDialog(BuildContext context, WidgetRef ref) async {
    final tokenController = TextEditingController();
    bool isLoading = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
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
                    controller: tokenController,
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
                  onPressed: isLoading
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  key: const Key('join_household_submit_button'),
                  onPressed: isLoading
                      ? null
                      : () async {
                          final raw = tokenController.text.trim();
                          if (raw.isEmpty) return;

                          // Extract the last path segment as the token.
                          final token = _extractToken(raw);
                          setDialogState(() => isLoading = true);

                          try {
                            await ref
                                .read(householdsNotifierProvider.notifier)
                                .joinByToken(token);

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  key: Key('join_success_snackbar'),
                                  content: Text('Successfully joined household!'),
                                ),
                              );
                            }
                          } on InviteExpiredException {
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  key: const Key('join_expired_snackbar'),
                                  content: const Text(
                                    'Invite link has expired or has already been used.',
                                  ),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.error,
                                ),
                              );
                            }
                          } on AlreadyMemberException {
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  key: const Key('join_already_member_snackbar'),
                                  content: const Text(
                                    'You are already a member of this household.',
                                  ),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.error,
                                ),
                              );
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              setDialogState(() => isLoading = false);
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString()),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.error,
                                ),
                              );
                            }
                          }
                        },
                  child: isLoading
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
          },
        );
      },
    );

    tokenController.dispose();
  }

  /// Extracts the token from a URL or returns the raw value as-is.
  ///
  /// For a URL like `https://example.com/invites/abc123/accept`,
  /// this returns `abc123`.
  String _extractToken(String raw) {
    try {
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        // Filter out empty and common suffix segments like "accept".
        final segments = uri.pathSegments
            .where((s) => s.isNotEmpty && s != 'accept')
            .toList();
        if (segments.isNotEmpty) {
          return segments.last;
        }
      }
    } catch (_) {
      // fall through to raw value
    }
    return raw;
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
