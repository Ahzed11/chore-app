/// Invite link response returned by `POST /households/{id}/invites`.
class InviteResponse {
  const InviteResponse({
    required this.token,
    required this.inviteUrl,
    required this.expiresAt,
  });

  final String token;
  final String inviteUrl;

  /// The expiry instant stored as UTC.
  final DateTime expiresAt;

  factory InviteResponse.fromJson(Map<String, dynamic> json) {
    return InviteResponse(
      token: json['token'] as String,
      inviteUrl: json['invite_url'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'invite_url': inviteUrl,
      'expires_at': expiresAt.toIso8601String(),
    };
  }
}
