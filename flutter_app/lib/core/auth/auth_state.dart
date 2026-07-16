import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_endpoints.dart';
import '../config/app_config.dart';

// ---------------------------------------------------------------------------
// Secure storage helpers
// ---------------------------------------------------------------------------

class AuthStorage {
  AuthStorage._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';

  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
  }

  static Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _refreshTokenKey, value: token);
  }

  static Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  static Future<void> clearRefreshToken() async {
    await _storage.delete(key: _refreshTokenKey);
  }
}

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.token,
  });

  final AuthStatus status;
  final String? token;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({AuthStatus? status, String? token}) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
    );
  }
}

// ---------------------------------------------------------------------------
// Auxiliary Dio for auth endpoints (refresh / logout)
// ---------------------------------------------------------------------------

/// A bare Dio (no auth interceptor, so no recursion) used for the refresh
/// and logout endpoints. Timeouts match `api_client.dart`. Overridden in
/// tests to inject a fake [HttpClientAdapter].
final authDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );
});

// ---------------------------------------------------------------------------
// Auth notifier
// ---------------------------------------------------------------------------

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _initialize();
    return const AuthState();
  }

  Future<void> _initialize() async {
    final token = await AuthStorage.getToken();
    if (token != null && token.isNotEmpty) {
      state = AuthState(status: AuthStatus.authenticated, token: token);
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> saveToken(String token) async {
    await AuthStorage.saveToken(token);
    state = AuthState(status: AuthStatus.authenticated, token: token);
  }

  Future<void> logout() async {
    // Best-effort server logout — swallow errors so local logout always completes.
    try {
      final token = await AuthStorage.getToken();
      if (token != null) {
        await ref.read(authDioProvider).post<void>(
              ApiEndpoints.authLogout(),
              options: Options(headers: {'Authorization': 'Bearer $token'}),
            );
      }
    } catch (_) {
      // ignore — local logout must always succeed
    }
    await AuthStorage.clearToken();
    await AuthStorage.clearRefreshToken();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> clearOnUnauthorized() async {
    await AuthStorage.clearToken();
    await AuthStorage.clearRefreshToken();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Attempts to refresh the access token using the stored refresh token.
  ///
  /// Returns `true` on success (new tokens persisted). On failure returns
  /// `false`; local auth state is cleared **only** when the refresh endpoint
  /// rejects the refresh token (HTTP 401/403). Transient network failures
  /// (timeouts, connection errors) and other errors leave the stored tokens
  /// intact so the caller can surface a recoverable error and retry later.
  Future<bool> refresh() async {
    final refreshToken = await AuthStorage.getRefreshToken();
    if (refreshToken == null) return false;
    try {
      final response = await ref.read(authDioProvider).post<Map<String, dynamic>>(
            ApiEndpoints.authRefresh(),
            data: {'refresh_token': refreshToken},
          );
      final data = response.data!;
      final newAccessToken = data['access_token'] as String;
      await AuthStorage.saveToken(newAccessToken);
      await AuthStorage.saveRefreshToken(data['refresh_token'] as String);
      state = AuthState(status: AuthStatus.authenticated, token: newAccessToken);
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        // The refresh token itself is invalid/expired — force re-login.
        await clearOnUnauthorized();
      }
      // Network/timeout/other HTTP errors: keep tokens, report transient failure.
      return false;
    } catch (_) {
      // Malformed success body or unexpected error — do not wipe tokens.
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
