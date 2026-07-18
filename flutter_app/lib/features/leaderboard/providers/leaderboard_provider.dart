import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../models/leaderboard_model.dart';

// Current-user-ID lookup used to be duplicated here as a client-side JWT
// decode of the stored access token. Standardized on `currentUserProvider`
// (`GET /users/me`, `features/auth/providers/current_user_provider.dart`)
// instead — see TASK-067 F-22.

// ---------------------------------------------------------------------------
// Scope notifier
// ---------------------------------------------------------------------------

class LeaderboardScopeNotifier extends Notifier<LeaderboardScope> {
  @override
  LeaderboardScope build() => LeaderboardScope.allTime;

  void setScope(LeaderboardScope scope) => state = scope;
}

final leaderboardScopeNotifierProvider =
    NotifierProvider<LeaderboardScopeNotifier, LeaderboardScope>(
  LeaderboardScopeNotifier.new,
);

// ---------------------------------------------------------------------------
// Leaderboard data provider
// ---------------------------------------------------------------------------

/// Family provider keyed by [householdId].
/// Re-runs automatically when the scope changes (via [ref.watch]).
final leaderboardProvider = FutureProvider.family<LeaderboardResult, String>(
  (ref, householdId) async {
    final scope = ref.watch(leaderboardScopeNotifierProvider);
    final dio = ref.watch(dioProvider);

    final response = await dio.get<Map<String, dynamic>>(
      ApiEndpoints.leaderboard(householdId),
      queryParameters: {'scope': scope.apiValue},
    );

    return LeaderboardResult.fromJson(response.data!);
  },
);

/// Always fetches this_week — used by the My Chores points banner.
final weeklyLeaderboardProvider = FutureProvider.family<LeaderboardResult, String>(
  (ref, householdId) async {
    final dio = ref.watch(dioProvider);
    final response = await dio.get<Map<String, dynamic>>(
      ApiEndpoints.leaderboard(householdId),
      queryParameters: {'scope': LeaderboardScope.thisWeek.apiValue},
    );
    return LeaderboardResult.fromJson(response.data!);
  },
);
