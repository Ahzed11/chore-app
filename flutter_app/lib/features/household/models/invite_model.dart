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

  /// Custom-scheme deep link the QR code encodes (TASK-061), e.g.
  /// `choreapp:///join/AbC123`.
  ///
  /// Deliberately built with an *empty* authority (three slashes) rather
  /// than `choreapp://join/<token>`: `Uri.parse` treats the segment right
  /// after `//` as the host, not the path, so `choreapp://join/AbC123`
  /// would parse with `host: 'join'` and `path: '/AbC123'` — losing "join"
  /// entirely. go_router matches routes against `uri.path` alone (the same
  /// way it matches universal `https://` links against a path, ignoring the
  /// domain), so an empty-authority URI is what's needed for this to land
  /// on the `/join/:token` route with zero extra glue code:
  /// `Uri.parse('choreapp:///join/AbC123').path == '/join/AbC123'`.
  ///
  /// [inviteUrl] (the backend's `https://` URL) remains what's copied to the
  /// clipboard and put in the OS share sheet — it's the one link guaranteed
  /// to do something useful (open a browser) even on a device that doesn't
  /// have ChoreApp installed yet. The `choreapp://` scheme only matters once
  /// the app *is* installed, where the OS intercepts it before it ever
  /// reaches a browser and routes straight into the app's join flow — which
  /// is exactly the case a scanned QR code is in.
  String get deepLink => 'choreapp:///join/$token';

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
