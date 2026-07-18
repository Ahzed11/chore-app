import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ---------------------------------------------------------------------------
// Persistent storage for the user-configured backend base URL.
//
// Reuses `flutter_secure_storage` (already a dependency for auth tokens)
// rather than adding `shared_preferences` for a single string value. The URL
// itself isn't sensitive, but keeping one storage mechanism avoids a second
// plugin, a second platform channel, and a second async-init pattern to
// reason about — and it mirrors `AuthStorage` in `core/auth/auth_state.dart`
// exactly, which keeps the codebase consistent.
// ---------------------------------------------------------------------------

class ServerConfigStorage {
  ServerConfigStorage._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _urlKey = 'server_base_url';

  static Future<String?> getUrl() => _storage.read(key: _urlKey);

  static Future<void> setUrl(String url) =>
      _storage.write(key: _urlKey, value: url);

  static Future<void> clearUrl() => _storage.delete(key: _urlKey);
}

// ---------------------------------------------------------------------------
// Validation / normalization for user-entered server URLs.
// ---------------------------------------------------------------------------

class ServerUrlValidation {
  ServerUrlValidation._();

  /// Returns the normalized URL — a valid absolute `http`/`https` URL with
  /// no trailing slash — or `null` if [input] is not a valid server URL.
  static String? normalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;

    var result = uri.toString();
    if (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
