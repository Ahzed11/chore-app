import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../leaderboard/providers/leaderboard_provider.dart';
import '../models/chore_model.dart';

// ---------------------------------------------------------------------------
// Chores notifier
// ---------------------------------------------------------------------------

class ChoresNotifier
    extends FamilyAsyncNotifier<List<ChoreModel>, String> {
  @override
  Future<List<ChoreModel>> build(String arg) async {
    return _fetchChores(arg);
  }

  /// Requests per page. The backend defaults to 50 and caps at 200; 100 keeps
  /// page count low while staying comfortably under that cap.
  static const int _pageSize = 100;

  /// Hard stop on the number of pages fetched so a backend bug (e.g. a
  /// `total` that never matches the accumulated item count) can't spin the
  /// client into an unbounded request loop.
  static const int _maxPages = 10;

  Future<List<ChoreModel>> _fetchChores(
    String householdId, {
    String? status,
    String? category,
    String? assigneeId,
  }) async {
    final dio = ref.read(dioProvider);

    final baseQueryParams = <String, String>{};
    if (status != null && status.isNotEmpty) {
      baseQueryParams['status'] = status;
    }
    if (category != null && category.isNotEmpty) {
      baseQueryParams['category'] = category;
    }
    if (assigneeId != null && assigneeId.isNotEmpty) {
      baseQueryParams['assignee_id'] = assigneeId;
    }

    // The backend truncates to `limit=50` per page by default; loop through
    // pages so households with >50 chore instances (recurring series build
    // up fast) get the full list instead of a silently truncated one.
    final items = <ChoreModel>[];
    var offset = 0;
    var total = 0;
    var pagesFetched = 0;

    do {
      final response = await dio.get<Map<String, dynamic>>(
        ApiEndpoints.householdChores(householdId),
        queryParameters: {
          ...baseQueryParams,
          'limit': '$_pageSize',
          'offset': '$offset',
        },
      );

      final data = response.data!;
      total = data['total'] as int? ?? 0;
      final pageItems = data['items'] as List<dynamic>;
      items.addAll(
        pageItems.cast<Map<String, dynamic>>().map(ChoreModel.fromJson),
      );

      offset += _pageSize;
      pagesFetched++;
    } while (items.length < total && pagesFetched < _maxPages);

    return items;
  }

  /// Marks a chore instance as complete.
  ///
  /// Uses an optimistic update for instant UI feedback. On failure the previous
  /// state is restored and the error is rethrown so callers can surface
  /// appropriate messages to the user.
  ///
  /// Returns the server's authoritative updated chore (with the real
  /// `pointsAwarded`) so callers can show it instead of a client-derived
  /// estimate.
  Future<ChoreModel> completeChore(String instanceId) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);

    // Snapshot current state so we can revert on failure.
    final previousState = state;

    // Optimistic update: immediately show the chore as complete.
    state = state.whenData((chores) => [
      for (final c in chores)
        if (c.id == instanceId)
          ChoreModel(
            id: c.id,
            definitionId: c.definitionId,
            householdId: c.householdId,
            assigneeId: c.assigneeId,
            assigneeName: c.assigneeName,
            assignedManually: c.assignedManually,
            dueDate: c.dueDate,
            status: 'complete',
            completedAt: DateTime.now(),
            pointsAwarded: c.pointValue,
            title: c.title,
            description: c.description,
            category: c.category,
            effortLevel: c.effortLevel,
            choreType: c.choreType,
          )
        else
          c,
    ]);

    try {
      final response = await dio.post<Map<String, dynamic>>(
        ApiEndpoints.choreComplete(householdId, instanceId),
      );
      // Replace optimistic entry with the authoritative server response.
      final updatedChore = ChoreModel.fromJson(response.data!);
      state = state.whenData((chores) => [
        for (final c in chores)
          if (c.id == instanceId) updatedChore else c,
      ]);

      // The rank pill (My Chores) and the Leaderboard tab both derive from
      // these providers; without invalidating them they'd keep showing
      // pre-completion standings until some unrelated refresh happened to
      // occur.
      ref.invalidate(leaderboardProvider(householdId));
      ref.invalidate(weeklyLeaderboardProvider(householdId));

      return updatedChore;
    } catch (e) {
      state = previousState; // revert on failure
      rethrow;
    }
  }

  /// Dismisses a chore instance — closes it as done with zero points and no
  /// PointLedger entry.
  ///
  /// Mirrors [completeChore]: optimistic update for instant UI feedback,
  /// replaced by the server's authoritative response on success, reverted on
  /// failure (error rethrown so callers can surface it).
  ///
  /// Deliberately does NOT invalidate the leaderboard providers — dismissing
  /// awards nothing, so standings are unchanged.
  Future<ChoreModel> dismissChore(String instanceId) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);

    // Snapshot current state so we can revert on failure.
    final previousState = state;

    // Optimistic update: immediately show the chore as dismissed (no points).
    state = state.whenData((chores) => [
      for (final c in chores)
        if (c.id == instanceId)
          ChoreModel(
            id: c.id,
            definitionId: c.definitionId,
            householdId: c.householdId,
            assigneeId: c.assigneeId,
            assigneeName: c.assigneeName,
            assignedManually: c.assignedManually,
            dueDate: c.dueDate,
            status: 'dismissed',
            completedAt: DateTime.now(),
            pointsAwarded: null,
            title: c.title,
            description: c.description,
            category: c.category,
            effortLevel: c.effortLevel,
            choreType: c.choreType,
          )
        else
          c,
    ]);

    try {
      final response = await dio.post<Map<String, dynamic>>(
        ApiEndpoints.choreDismiss(householdId, instanceId),
      );
      // Replace optimistic entry with the authoritative server response.
      final updatedChore = ChoreModel.fromJson(response.data!);
      state = state.whenData((chores) => [
        for (final c in chores)
          if (c.id == instanceId) updatedChore else c,
      ]);
      return updatedChore;
    } catch (e) {
      state = previousState; // revert on failure
      rethrow;
    }
  }

  /// Creates a new chore definition and its first instance. Admin only.
  Future<void> createChore(Map<String, dynamic> body) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      ApiEndpoints.householdChores(householdId),
      data: body,
    );
    ref.invalidateSelf();
    await future;
  }

  /// Updates an existing chore definition. Changes affect future instances
  /// only. Admin only.
  Future<void> updateChoreDefinition(
    String definitionId,
    Map<String, dynamic> body,
  ) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      ApiEndpoints.choreDefinition(householdId, definitionId),
      data: body,
    );
    ref.invalidateSelf();
    await future;
  }

  /// Soft-deletes an entire chore series. Admin only.
  Future<void> deleteChore(String definitionId) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);
    await dio.delete<void>(
      ApiEndpoints.choreDefinition(householdId, definitionId),
    );
    ref.invalidateSelf();
    await future;
  }

  /// Reassigns a chore instance to [assigneeId]. Admin only.
  ///
  /// Refreshes the chore list from the server on success so the card reflects
  /// the new assignee name.
  Future<void> reassignChore(String instanceId, String assigneeId) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      ApiEndpoints.choreAssignee(householdId, instanceId),
      data: {'assignee_id': assigneeId},
    );
    ref.invalidateSelf();
    await future;
  }

  /// Forces a fresh fetch from the server.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final choresNotifierProvider = AsyncNotifierProviderFamily<ChoresNotifier,
    List<ChoreModel>, String>(ChoresNotifier.new);
