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
