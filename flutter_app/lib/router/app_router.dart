import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_state.dart';
import '../core/config/server_url_provider.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/chores/models/chore_form_init_data.dart';
import '../features/chores/screens/chore_list_screen.dart';
import '../features/chores/screens/create_chore_screen.dart';
import '../features/chores/screens/my_chores_screen.dart';
import '../features/groceries/screens/grocery_list_screen.dart';
import '../features/household/providers/pending_join_provider.dart';
import '../features/household/screens/household_dashboard_screen.dart';
import '../features/household/screens/household_management_screen.dart';
import '../features/household/screens/join_invite_screen.dart';
import '../features/leaderboard/screens/leaderboard_screen.dart';
import '../features/server/screens/server_setup_screen.dart';
import '../shared/widgets/splash_screen.dart';

// ---------------------------------------------------------------------------
// Route name constants
// ---------------------------------------------------------------------------

class AppRoutes {
  AppRoutes._();

  static const String splash = 'splash';
  static const String login = 'login';
  static const String register = 'register';
  static const String serverSetup = 'server-setup';
  static const String households = 'households';
  static const String choreList = 'chore-list';
  static const String myChores = 'my-chores';
  static const String leaderboard = 'leaderboard';
  static const String groceryList = 'grocery-list';
  static const String householdManage = 'household-manage';
  static const String createChore = 'create-chore';
  static const String joinInvite = 'join-invite';
}

// ---------------------------------------------------------------------------
// Navigation helpers
// ---------------------------------------------------------------------------

/// Navigates to the server-setup screen so the user can point the app at a
/// different server. Unlike the mandatory first-run redirect, this shows a
/// cancel button (`canCancel: true`) since a server is already configured.
void goToChangeServer(BuildContext context) {
  context.pushNamed(AppRoutes.serverSetup, extra: const {'canCancel': true});
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
  // Listenable that triggers router refresh when auth or server-config
  // state changes.
  final appState = _AppStateListenable(ref);

  return GoRouter(
    refreshListenable: appState,
    initialLocation: '/splash',
    redirect: (BuildContext context, GoRouterState state) {
      final serverState = ref.read(serverUrlProvider);
      final isOnSplash = state.matchedLocation == '/splash';
      final isOnServerSetup = state.matchedLocation == '/server-setup';

      // Still resolving the persisted server URL from secure storage — hold
      // on the splash screen (TASK-067 F-25) instead of flashing whatever
      // route happens to render first, only to redirect away a moment later.
      if (serverState.status == ServerUrlStatus.unknown) {
        return isOnSplash ? null : '/splash';
      }

      // No server configured yet — first-run setup screen, before login,
      // regardless of auth state.
      if (serverState.status == ServerUrlStatus.unconfigured) {
        return isOnServerSetup ? null : '/server-setup';
      }

      // Server is configured — fall through to the usual auth-route
      // redirects below. These already do the right thing for
      // `/server-setup` without a special case: an unauthenticated user who
      // just finished first-run setup (or just changed servers, which logs
      // them out) is bounced to `/login` same as any other non-auth route;
      // an authenticated user who voluntarily navigated here to change the
      // server (and hasn't submitted yet) is authenticated + not on an auth
      // route, so neither branch fires and they're left alone to fill in
      // the form or cancel.
      final authState = ref.read(authNotifierProvider);

      // Still resolving token from secure storage — same cold-start flash
      // this used to cause on `/login` (TASK-067 F-25).
      if (authState.status == AuthStatus.unknown) {
        return isOnSplash ? null : '/splash';
      }

      final isAuthenticated = authState.isAuthenticated;
      final isOnAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      // Invite deep link (`/join/:token`, TASK-061). An unauthenticated
      // visitor (fresh install, or logged out) can't join yet — stash the
      // token and send them through the normal login/registration flow
      // first; the `isAuthenticated && (isOnAuthRoute || isOnSplash)` branch
      // below routes them straight back here once they're signed in. This
      // runs *after* the unconfigured-server check above, so a deep link
      // opened on a fresh install already goes
      // server-setup → login/register → join, as required.
      final isOnJoinRoute = state.matchedLocation.startsWith('/join/');
      if (isOnJoinRoute && !isAuthenticated) {
        final token = state.pathParameters['token'];
        if (token != null && token.isNotEmpty) {
          ref.read(pendingJoinTokenProvider.notifier).stash(token);
        }
        return '/login';
      }

      if (!isAuthenticated && !isOnAuthRoute) {
        return '/login';
      }

      // Both the ordinary "just logged in from /login or /register" case
      // and "auth/server status just finished resolving while still sitting
      // on /splash" land here — either way, an authenticated user shouldn't
      // stay on either screen.
      if (isAuthenticated && (isOnAuthRoute || isOnSplash)) {
        final pendingToken = ref.read(pendingJoinTokenProvider);
        if (pendingToken != null) {
          return '/join/$pendingToken';
        }
        return '/households';
      }

      return null;
    },
    routes: [
      // Splash — shown only while the persisted server URL / auth token are
      // being resolved from secure storage; the redirect above always moves
      // on from here once that resolves.
      GoRoute(
        path: '/splash',
        name: AppRoutes.splash,
        pageBuilder: (context, state) => _tabPage(state, const SplashScreen()),
      ),

      // Server setup — shown first-run (before login) when no URL is
      // configured, and reachable later to change the server.
      GoRoute(
        path: '/server-setup',
        name: AppRoutes.serverSetup,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final canCancel = extra?['canCancel'] == true;
          return _tabPage(state, ServerSetupScreen(canCancel: canCancel));
        },
      ),

      // Auth routes — simple fade so the login↔register transition isn't jarring
      GoRoute(
        path: '/login',
        name: AppRoutes.login,
        pageBuilder: (context, state) => _tabPage(state, const LoginScreen()),
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
      GoRoute(
        path: '/households/:householdId/groceries',
        name: AppRoutes.groceryList,
        pageBuilder: (context, state) {
          final id = state.pathParameters['householdId']!;
          return _tabPage(state, GroceryListScreen(householdId: id));
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
            state,
            CreateChoreScreen(householdId: id, initData: initData),
          );
        },
      ),
      // Invite deep link — `choreapp:///join/:token` (custom scheme, see
      // `InviteResponse.deepLink`) as well as anyone who pastes the path
      // directly. Only ever rendered while authenticated; see the
      // `isOnJoinRoute` handling in `redirect` above for the logged-out case.
      GoRoute(
        path: '/join/:token',
        name: AppRoutes.joinInvite,
        pageBuilder: (context, state) {
          final token = state.pathParameters['token']!;
          return _tabPage(state, JoinInviteScreen(token: token));
        },
      ),
    ],
  );
});

// ---------------------------------------------------------------------------
// App state change listenable (bridges Riverpod -> GoRouter refresh)
// ---------------------------------------------------------------------------

class _AppStateListenable extends ChangeNotifier {
  _AppStateListenable(Ref ref) {
    _authSubscription = ref.listen<AuthState>(
      authNotifierProvider,
      (_, __) => notifyListeners(),
    );
    _serverSubscription = ref.listen<ServerUrlState>(
      serverUrlProvider,
      (_, __) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AuthState> _authSubscription;
  late final ProviderSubscription<ServerUrlState> _serverSubscription;

  @override
  void dispose() {
    _authSubscription.close();
    _serverSubscription.close();
    super.dispose();
  }
}
