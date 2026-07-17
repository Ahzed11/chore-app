import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/friendly_error.dart';
import '../../../router/app_router.dart';
import '../providers/household_provider.dart';
import '../providers/pending_join_provider.dart';

// ---------------------------------------------------------------------------
// JoinInviteScreen (TASK-061)
// ---------------------------------------------------------------------------

/// Hosted at the `/join/:token` route. Only ever reached while authenticated
/// — the router's `redirect` stashes the token and bounces an unauthenticated
/// visitor to `/login` first (see `router/app_router.dart`), then routes
/// back here automatically once login/registration succeeds.
///
/// Runs the existing `joinByToken` flow on mount, then navigates to the
/// joined household (or back to the households list on failure) with the
/// same error handling `HouseholdDashboardScreen`'s manual join dialog uses.
class JoinInviteScreen extends ConsumerStatefulWidget {
  const JoinInviteScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<JoinInviteScreen> createState() => _JoinInviteScreenState();
}

class _JoinInviteScreenState extends ConsumerState<JoinInviteScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _join());
  }

  Future<void> _join() async {
    // Clear the stash immediately, before the request even starts: if the
    // join fails and the user is later bounced back through `/login` for an
    // unrelated reason, a stale token must not silently re-fire.
    ref.read(pendingJoinTokenProvider.notifier).clear();

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      final household = await ref
          .read(householdsNotifierProvider.notifier)
          .joinByToken(widget.token);
      if (!mounted) return;
      router.goNamed(
        AppRoutes.choreList,
        pathParameters: {'householdId': household.id},
      );
      messenger.showSnackBar(
        const SnackBar(
          key: Key('join_success_snackbar'),
          content: Text('Successfully joined household!'),
        ),
      );
    } on InviteExpiredException catch (e) {
      _fail(router, messenger, errorColor, e.toString(),
          key: 'join_expired_snackbar');
    } on AlreadyMemberException catch (e) {
      _fail(router, messenger, errorColor, e.toString(),
          key: 'join_already_member_snackbar');
    } catch (e) {
      _fail(router, messenger, errorColor, friendlyErrorMessage(e));
    }
  }

  void _fail(
    GoRouter router,
    ScaffoldMessengerState messenger,
    Color errorColor,
    String message, {
    String? key,
  }) {
    if (!mounted) return;
    router.go('/households');
    messenger.showSnackBar(
      SnackBar(
        key: key != null ? Key(key) : null,
        content: Text(message),
        backgroundColor: errorColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(key: Key('join_loading_indicator')),
      ),
    );
  }
}
