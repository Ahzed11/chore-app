/// A previous chore definition offered as a create-form template (TASK-106/107).
///
/// Carries exactly the fields that get copied into the create form:
/// title, description, category and effort level (the "score").
class ChoreTemplate {
  const ChoreTemplate({
    required this.id,
    required this.title,
    this.description,
    required this.category,
    required this.effortLevel,
  });

  final String id;
  final String title;
  final String? description;
  final String category;
  final String effortLevel; // easy | medium | hard

  factory ChoreTemplate.fromJson(Map<String, dynamic> json) {
    return ChoreTemplate(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      category: json['category'] as String,
      effortLevel: json['effort_level'] as String,
    );
  }
}
