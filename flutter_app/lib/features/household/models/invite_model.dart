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

/// Metadata for an existing active (non-expired, unused) invite token as
/// returned by `GET /households/{id}/invites`.
///
/// Unlike [InviteResponse] (returned only once, at creation time via
/// `POST /households/{id}/invites`), this does *not* include the full token
/// or invite URL — only a masked preview (`token_preview`, e.g. `"aB3dEf12***"`)
/// since the backend never re-exposes a full token after generation.
class InviteTokenSummary {
  const InviteTokenSummary({
    required this.id,
    required this.tokenPreview,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String tokenPreview;
  final DateTime createdAt;
  final DateTime expiresAt;

  factory InviteTokenSummary.fromJson(Map<String, dynamic> json) {
    return InviteTokenSummary(
      id: json['id'] as String,
      tokenPreview: json['token_preview'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    );
  }
}
