import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../leaderboard/providers/leaderboard_provider.dart';
import '../models/chore_model.dart';

// ---------------------------------------------------------------------------
// Filter state
// ---------------------------------------------------------------------------

class ChoreFilter {
  const ChoreFilter({
    this.status,
    this.category,
    this.assigneeId,
  });

  /// null → show all statuses
  final String? status;

  /// null → show all categories
  final String? category;

  /// null → show all assignees
  final String? assigneeId;

  ChoreFilter copyWith({
    Object? status = _sentinel,
    Object? category = _sentinel,
    Object? assigneeId = _sentinel,
  }) {
    return ChoreFilter(
      status: status == _sentinel ? this.status : status as String?,
      category: category == _sentinel ? this.category : category as String?,
      assigneeId:
          assigneeId == _sentinel ? this.assigneeId : assigneeId as String?,
    );
  }

  static const Object _sentinel = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChoreFilter &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          category == other.category &&
          assigneeId == other.assigneeId;

  @override
  int get hashCode =>
      status.hashCode ^ category.hashCode ^ assigneeId.hashCode;
}

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

// ---------------------------------------------------------------------------
// Filter notifier
// ---------------------------------------------------------------------------

class ChoreFilterNotifier extends Notifier<ChoreFilter> {
  @override
  ChoreFilter build() => const ChoreFilter();

  void setStatus(String? status) {
    state = state.copyWith(status: status);
  }

  void setCategory(String? category) {
    state = state.copyWith(category: category);
  }

  /// Toggles "my chores only" for [currentUserId]. If already filtering by
  /// that user, clears the filter.
  void toggleMyChoresOnly(String currentUserId) {
    if (state.assigneeId == currentUserId) {
      state = state.copyWith(assigneeId: null);
    } else {
      state = state.copyWith(assigneeId: currentUserId);
    }
  }

  void clearAssigneeFilter() {
    state = state.copyWith(assigneeId: null);
  }
}

final choreFilterNotifierProvider =
    NotifierProvider<ChoreFilterNotifier, ChoreFilter>(
  ChoreFilterNotifier.new,
);
