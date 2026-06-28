import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';

// ---------------------------------------------------------------------------
// Current user profile
// ---------------------------------------------------------------------------

class UserProfile {
  const UserProfile({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

/// Fetches the authenticated user's profile from GET /users/me.
///
/// Override this in tests to avoid real network calls.
final currentUserProvider = FutureProvider<UserProfile>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get<Map<String, dynamic>>(ApiEndpoints.me);
  final data = response.data!;
  return UserProfile(
    id: data['id'] as String,
    displayName: data['display_name'] as String? ?? '',
  );
});
