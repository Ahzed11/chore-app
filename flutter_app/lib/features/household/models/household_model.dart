class HouseholdModel {
  const HouseholdModel({
    required this.id,
    required this.name,
    required this.role,
    required this.memberCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String role; // "admin" or "member"
  final int memberCount;
  final DateTime createdAt;

  bool get isAdmin => role == 'admin';

  factory HouseholdModel.fromJson(Map<String, dynamic> json) {
    return HouseholdModel(
      id: json['id'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      memberCount: json['member_count'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  HouseholdModel copyWith({
    String? id,
    String? name,
    String? role,
    int? memberCount,
    DateTime? createdAt,
  }) {
    return HouseholdModel(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      memberCount: memberCount ?? this.memberCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'member_count': memberCount,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
