import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_state.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/chores/models/chore_form_init_data.dart';
import '../features/chores/screens/chore_list_screen.dart';
import '../features/chores/screens/create_chore_screen.dart';
import '../features/chores/screens/my_chores_screen.dart';
import '../features/household/models/invite_model.dart';
import '../features/household/screens/household_dashboard_screen.dart';
import '../features/household/screens/household_management_screen.dart';
import '../features/household/screens/invite_screen.dart';
import '../features/leaderboard/screens/leaderboard_screen.dart';

// ---------------------------------------------------------------------------
// Route name constants
// ---------------------------------------------------------------------------

class AppRoutes {
  AppRoutes._();

  static const String login = 'login';
  static const String register = 'register';
  static const String households = 'households';
  static const String choreList = 'chore-list';
  static const String myChores = 'my-chores';
  static const String leaderboard = 'leaderboard';
  static const String householdManage = 'household-manage';
  static const String createChore = 'create-chore';
  static const String invite = 'invite';
}

// ---------------------------------------------------------------------------
// Transition helpers
// ---------------------------------------------------------------------------

/// Fade transition for tab-level navigation (bottom nav switches).
/// Instant-feeling at 200 ms — no directional bias.
Page<void> _tabPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

/// Slide-from-right for child / detail screens pushed on top of a tab.
Page<void> _slidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic),
      ),
      child: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Router provider
// ---------------------------------------------------------------------------

final appRouterProvider = Provider<GoRouter>((ref) {
  // Listenable that triggers router refresh when auth state changes.
  final authNotifier = _AuthStateListenable(ref);

  return GoRouter(
    refreshListenable: authNotifier,
    initialLocation: '/login',
    redirect: (BuildContext context, GoRouterState state) {
      final authState = ref.read(authNotifierProvider);

      // Still resolving token from secure storage.
      if (authState.status == AuthStatus.unknown) {
        return null; // Let through; will refresh once resolved.
      }

      final isAuthenticated = authState.isAuthenticated;
      final isOnAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!isAuthenticated && !isOnAuthRoute) {
        return '/login';
      }

      if (isAuthenticated && isOnAuthRoute) {
        return '/households';
      }

      return null;
    },
    routes: [
      // Auth routes — simple fade so the login↔register transition isn't jarring
      GoRoute(
        path: '/login',
        name: AppRoutes.login,
        pageBuilder: (context, state) =>
            _tabPage(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        name: AppRoutes.register,
        pageBuilder: (context, state) =>
            _tabPage(state, const RegisterScreen()),
      ),

      // Household dashboard — fade (top-level, like a tab)
      GoRoute(
        path: '/households',
        name: AppRoutes.households,
        pageBuilder: (context, state) =>
            _tabPage(state, const HouseholdDashboardScreen()),
      ),

      // ── Tab screens — fade so bottom-nav switches feel instant ──────────
      GoRoute(
        path: '/households/:householdId/chores',
        name: AppRoutes.choreList,
        pageBuilder: (context, state) {
          final id = state.pathParameters['householdId']!;
          return _tabPage(state, ChoreListScreen(householdId: id));
        },
      ),
      GoRoute(
        path: '/households/:householdId/my-chores',
        name: AppRoutes.myChores,
        pageBuilder: (context, state) {
          final id = state.pathParameters['householdId']!;
          return _tabPage(state, MyChoresScreen(householdId: id));
        },
      ),
      GoRoute(
        path: '/households/:householdId/leaderboard',
        name: AppRoutes.leaderboard,
        pageBuilder: (context, state) {
          final id = state.pathParameters['householdId']!;
          return _tabPage(state, LeaderboardScreen(householdId: id));
        },
      ),

      // ── Child / detail screens — slide from right ────────────────────────
      GoRoute(
        path: '/households/:householdId/manage',
        name: AppRoutes.householdManage,
        pageBuilder: (context, state) {
          final id = state.pathParameters['householdId']!;
          return _slidePage(state, HouseholdManagementScreen(householdId: id));
        },
      ),
      GoRoute(
        path: '/households/:householdId/chores/create',
        name: AppRoutes.createChore,
        pageBuilder: (context, state) {
          final id = state.pathParameters['householdId']!;
          final initData = state.extra as ChoreFormInitData?;
          return _slidePage(
              state, CreateChoreScreen(householdId: id, initData: initData));
        },
      ),
      GoRoute(
        path: '/households/:householdId/invite',
        name: AppRoutes.invite,
        pageBuilder: (context, state) {
          final id = state.pathParameters['householdId']!;
          final extra = state.extra as Map<String, dynamic>?;
          final initialInvite =
              extra != null ? InviteResponse.fromJson(extra) : null;
          return _slidePage(
              state, InviteScreen(householdId: id, initialInvite: initialInvite));
        },
      ),
    ],
  );
});

// ---------------------------------------------------------------------------
// Auth state change listenable (bridges Riverpod -> GoRouter refresh)
// ---------------------------------------------------------------------------

class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable(Ref ref) {
    _subscription = ref.listen<AuthState>(
      authNotifierProvider,
      (_, __) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
