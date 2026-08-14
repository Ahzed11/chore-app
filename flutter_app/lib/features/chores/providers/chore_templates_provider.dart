import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../models/chore_template.dart';

// ---------------------------------------------------------------------------
// Chore template suggestions (TASK-107)
// ---------------------------------------------------------------------------

class ChoreTemplatesNotifier
    extends FamilyAsyncNotifier<List<ChoreTemplate>, String> {
  @override
  Future<List<ChoreTemplate>> build(String householdId) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get<List<dynamic>>(
      ApiEndpoints.choreTemplates(householdId),
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(ChoreTemplate.fromJson)
        .toList();
  }

  /// Hides a template from the suggestions (admin only).
  ///
  /// Updates `state` directly by filtering the id out (TASK-092 pattern) —
  /// no `invalidateSelf` after a mutation. On failure the error is rethrown
  /// so callers can surface `friendlyErrorMessage`.
  Future<void> hideTemplate(String definitionId) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);
    await dio.post<void>(
      ApiEndpoints.choreHideTemplate(householdId, definitionId),
    );
    state = state.whenData(
      (list) => list.where((t) => t.id != definitionId).toList(),
    );
  }

  /// Forces a fresh fetch from the server.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final choreTemplatesProvider =
    AsyncNotifierProvider.family<ChoreTemplatesNotifier, List<ChoreTemplate>,
        String>(ChoreTemplatesNotifier.new);
