import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../models/household_model.dart';
import 'members_provider.dart';

// ---------------------------------------------------------------------------
// Custom exceptions
// ---------------------------------------------------------------------------

class InviteExpiredException implements Exception {
  const InviteExpiredException();

  @override
  String toString() => 'Invite link has expired or has already been used.';
}

class AlreadyMemberException implements Exception {
  const AlreadyMemberException();

  @override
  String toString() => 'You are already a member of this household.';
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class HouseholdsNotifier
    extends AsyncNotifier<List<HouseholdModel>> {
  @override
  Future<List<HouseholdModel>> build() async {
    return _fetchHouseholds();
  }

  Future<List<HouseholdModel>> _fetchHouseholds() async {
    final dio = ref.read(dioProvider);
    final response = await dio.get<List<dynamic>>(ApiEndpoints.households);
    final data = response.data ?? [];
    return data
        .cast<Map<String, dynamic>>()
        .map(HouseholdModel.fromJson)
        .toList();
  }

  /// Creates a new household and refreshes the list.
  Future<void> createHousehold(String name) async {
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      ApiEndpoints.households,
      data: {'name': name},
    );
    ref.invalidateSelf();
    await future;
  }

  /// Updates the name of a household and refreshes the list.
  Future<void> updateHouseholdName(String householdId, String newName) async {
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      ApiEndpoints.household(householdId),
      data: {'name': newName},
    );
    ref.invalidateSelf();
    await future;
  }

  /// Leaves a household.
  ///
  /// Throws [SoleAdminException] for HTTP 409.
  Future<void> leaveHousehold(String householdId) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.post<void>(ApiEndpoints.householdLeave(householdId));
      ref.invalidateSelf();
      await future;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw const SoleAdminException(
          'You are the sole admin. Promote another member first.',
        );
      }
      rethrow;
    }
  }

  /// Joins a household by invite token and refreshes the list.
  ///
  /// Throws [InviteExpiredException] for HTTP 410.
  /// Throws [AlreadyMemberException] for HTTP 409.
  Future<HouseholdModel> joinByToken(String token) async {
    final dio = ref.read(dioProvider);
    try {
      final response = await dio.post<Map<String, dynamic>>(
        ApiEndpoints.acceptInvite(token),
      );
      final household = HouseholdModel.fromJson(response.data!);
      ref.invalidateSelf();
      await future;
      return household;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 410) {
        throw const InviteExpiredException();
      }
      if (statusCode == 409) {
        throw const AlreadyMemberException();
      }
      rethrow;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final householdsNotifierProvider =
    AsyncNotifierProvider<HouseholdsNotifier, List<HouseholdModel>>(
  HouseholdsNotifier.new,
);

// Keep the selectedHouseholdIdProvider for backwards compatibility
// with any references elsewhere in the codebase.
final selectedHouseholdIdProvider = StateProvider<String?>((ref) => null);
