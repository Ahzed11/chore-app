import 'chore_model.dart';

/// Data used to pre-populate [CreateChoreScreen] when it is opened in edit
/// mode. Carries the chore-definition fields that are editable by an admin.
///
/// Populate this from a [ChoreModel] (or a dedicated definition endpoint) and
/// pass it as [GoRouterState.extra] or directly to the screen constructor.
class ChoreFormInitData {
  const ChoreFormInitData({
    required this.definitionId,
    required this.title,
    this.description,
    required this.category,
    required this.effortLevel,
    required this.choreType,
    this.firstDueDate,
    this.intervalUnit,
    this.intervalN,
    this.assigneeId,
  });

  /// Builds [ChoreFormInitData] from a chore *instance* (TASK-060) — the
  /// only shape the app has on hand when the admin long-presses a card in
  /// the list, since there's no dedicated "fetch chore definition" endpoint.
  ///
  /// [ChoreModel] doesn't carry the definition's recurrence rule (interval
  /// unit/count) — only the instance's own [ChoreModel.dueDate] — so
  /// [intervalUnit]/[intervalN] are left null here; the form falls back to
  /// its own defaults ("every 1 week") for those two fields specifically
  /// when editing a recurring chore. Everything else pre-populates exactly.
  factory ChoreFormInitData.fromModel(ChoreModel chore) {
    return ChoreFormInitData(
      definitionId: chore.definitionId,
      title: chore.title,
      description: chore.description,
      category: chore.category,
      effortLevel: chore.effortLevel,
      choreType: chore.choreType,
      firstDueDate: chore.dueDate,
      assigneeId: chore.assigneeId,
    );
  }

  /// The ID of the chore definition being edited (used in the PATCH URL).
  final String definitionId;

  final String title;
  final String? description;

  /// One of the category keys from [categoryLabels] in chore_model.dart.
  final String category;

  /// `easy` | `medium` | `hard`
  final String effortLevel;

  /// `one_off` | `recurring`
  final String choreType;

  /// For one-off chores this is the single due date; for recurring it is the
  /// date of the first generated instance.
  final DateTime? firstDueDate;

  /// `days` | `weeks` | `months`  (only meaningful when [choreType] is
  /// `recurring`).
  final String? intervalUnit;

  /// How many [intervalUnit]s between recurrences (min 1).
  final int? intervalN;

  final String? assigneeId;
}
