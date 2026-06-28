import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../models/member_model.dart';

// ---------------------------------------------------------------------------
// Custom exceptions
// ---------------------------------------------------------------------------

class SoleAdminException implements Exception {
  final String message;
  const SoleAdminException(this.message);

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class MembersNotifier
    extends FamilyAsyncNotifier<List<MemberModel>, String> {
  @override
  Future<List<MemberModel>> build(String arg) async {
    return _fetchMembers(arg);
  }

  Future<List<MemberModel>> _fetchMembers(String householdId) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get<List<dynamic>>(
      ApiEndpoints.householdMembers(householdId),
    );
    final data = response.data ?? [];
    return data
        .cast<Map<String, dynamic>>()
        .map(MemberModel.fromJson)
        .toList();
  }

  /// Changes the role of a member and refreshes the list.
  Future<void> changeRole(String userId, String newRole) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      ApiEndpoints.householdMemberRole(householdId, userId),
      data: {'role': newRole},
    );
    ref.invalidateSelf();
    await future;
  }

  /// Removes a member from the household and refreshes the list.
  ///
  /// Throws [SoleAdminException] when the API returns HTTP 409.
  Future<void> removeMember(String userId) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);
    try {
      await dio.delete<void>(
        ApiEndpoints.householdMember(householdId, userId),
      );
      ref.invalidateSelf();
      await future;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw const SoleAdminException(
          'Cannot remove the sole admin.',
        );
      }
      rethrow;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final membersNotifierProvider = AsyncNotifierProviderFamily<
    MembersNotifier, List<MemberModel>, String>(MembersNotifier.new);

