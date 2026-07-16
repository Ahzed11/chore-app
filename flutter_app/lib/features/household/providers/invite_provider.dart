import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../models/invite_model.dart';

// ---------------------------------------------------------------------------
// Abstract API interface — enables easy fakes in widget tests
// ---------------------------------------------------------------------------

abstract class InviteApi {
  Future<InviteResponse> generateInvite(String householdId);

  /// Lists active (non-expired, non-used) invite tokens for a household.
  Future<List<InviteTokenSummary>> listInvites(String householdId);

  /// Revokes (immediately expires) an invite token.
  Future<void> revokeInvite(String householdId, String inviteId);
}

// ---------------------------------------------------------------------------
// Concrete implementation backed by Dio
// ---------------------------------------------------------------------------

class InviteApiImpl implements InviteApi {
  const InviteApiImpl(this._dio);

  final Dio _dio;

  /// Calls `POST /households/{householdId}/invites` and returns the response.
  @override
  Future<InviteResponse> generateInvite(String householdId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.householdInvites(householdId),
    );
    return InviteResponse.fromJson(response.data!);
  }

  /// Calls `GET /households/{householdId}/invites`. The backend returns a
  /// bare JSON array of `InviteTokenResponse` objects (no envelope).
  @override
  Future<List<InviteTokenSummary>> listInvites(String householdId) async {
    final response = await _dio.get<List<dynamic>>(
      ApiEndpoints.householdInvites(householdId),
    );
    final data = response.data ?? [];
    return data
        .cast<Map<String, dynamic>>()
        .map(InviteTokenSummary.fromJson)
        .toList();
  }

  /// Calls `DELETE /households/{householdId}/invites/{inviteId}`. The
  /// backend responds with `204 No Content` on success.
  @override
  Future<void> revokeInvite(String householdId, String inviteId) async {
    await _dio.delete<void>(
      ApiEndpoints.revokeInvite(householdId, inviteId),
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final inviteApiProvider = Provider<InviteApi>((ref) {
  return InviteApiImpl(ref.watch(dioProvider));
});

/// Active invite tokens for a household. Fetched via `GET
/// /households/{id}/invites` — a lightweight listing (masked previews only,
/// no full tokens/URLs). Callers should `ref.invalidate` this after
/// generating or revoking an invite to keep the list in sync.
final invitesProvider =
    FutureProvider.family<List<InviteTokenSummary>, String>(
  (ref, householdId) => ref.watch(inviteApiProvider).listInvites(householdId),
);
