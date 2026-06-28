import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_state.dart';
import '../models/leaderboard_model.dart';

// ---------------------------------------------------------------------------
// Current user ID provider
// ---------------------------------------------------------------------------

/// Decodes the `sub` claim from the stored JWT without verifying the
/// signature — only used for UI highlighting of the current user's row.
///
/// Returns null when the user is not authenticated or the token cannot be
/// parsed.
final currentUserIdProvider = Provider<String?>((ref) {
  final token = ref.watch(authNotifierProvider).token;
  if (token == null || token.isEmpty) return null;

  try {
    final parts = token.split('.');
    if (parts.length < 2) return null;

    // Base64-url decode the payload section (index 1).
    String payload = parts[1];
    // Normalise padding to a multiple of 4.
    switch (payload.length % 4) {
      case 2:
        payload += '==';
      case 3:
        payload += '=';
    }
    // Convert URL-safe alphabet to standard base64.
    payload = payload.replaceAll('-', '+').replaceAll('_', '/');

    final decoded = utf8.decode(base64.decode(payload));
    final claims = jsonDecode(decoded) as Map<String, dynamic>;
    return claims['sub'] as String?;
  } catch (_) {
    return null;
  }
});

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
