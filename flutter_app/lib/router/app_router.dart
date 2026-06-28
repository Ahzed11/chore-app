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
      // Auth routes
      GoRoute(
        path: '/login',
        name: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),

      // Household dashboard
      GoRoute(
        path: '/households',
        name: AppRoutes.households,
        builder: (context, state) => const HouseholdDashboardScreen(),
      ),

      // Household-scoped routes
      GoRoute(
        path: '/households/:householdId/chores',
        name: AppRoutes.choreList,
        builder: (context, state) {
          final id = state.pathParameters['householdId']!;
          return ChoreListScreen(householdId: id);
        },
      ),
      GoRoute(
        path: '/households/:householdId/my-chores',
        name: AppRoutes.myChores,
        builder: (context, state) {
          final id = state.pathParameters['householdId']!;
          return MyChoresScreen(householdId: id);
        },
      ),
      GoRoute(
        path: '/households/:householdId/leaderboard',
        name: AppRoutes.leaderboard,
        builder: (context, state) {
          final id = state.pathParameters['householdId']!;
          return LeaderboardScreen(householdId: id);
        },
      ),
      GoRoute(
        path: '/households/:householdId/manage',
        name: AppRoutes.householdManage,
        builder: (context, state) {
          final id = state.pathParameters['householdId']!;
          return HouseholdManagementScreen(householdId: id);
        },
      ),
      GoRoute(
        path: '/households/:householdId/chores/create',
        name: AppRoutes.createChore,
        builder: (context, state) {
          final id = state.pathParameters['householdId']!;
          // state.extra is non-null when navigating to edit an existing chore.
          final initData = state.extra as ChoreFormInitData?;
          return CreateChoreScreen(householdId: id, initData: initData);
        },
      ),
      GoRoute(
        path: '/households/:householdId/invite',
        name: AppRoutes.invite,
        builder: (context, state) {
          final id = state.pathParameters['householdId']!;
          // HouseholdManagementScreen navigates here with the API response
          // already fetched and passed as extra — reuse it to avoid a duplicate
          // network call.  When navigating directly (deep link / refresh) the
          // extra is null and InviteScreen fetches on init instead.
          final extra = state.extra as Map<String, dynamic>?;
          final initialInvite =
              extra != null ? InviteResponse.fromJson(extra) : null;
          return InviteScreen(
            householdId: id,
            initialInvite: initialInvite,
          );
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
