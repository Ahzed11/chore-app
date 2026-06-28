class MemberModel {
  const MemberModel({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
  });

  final String userId;
  final String displayName;
  final String role;
  final DateTime joinedAt;

  bool get isAdmin => role == 'admin';

  factory MemberModel.fromJson(Map<String, dynamic> json) {
    return MemberModel(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  MemberModel copyWith({
    String? userId,
    String? displayName,
    String? role,
    DateTime? joinedAt,
  }) {
    return MemberModel(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }
}
