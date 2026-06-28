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
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final inviteApiProvider = Provider<InviteApi>((ref) {
  return InviteApiImpl(ref.watch(dioProvider));
});
