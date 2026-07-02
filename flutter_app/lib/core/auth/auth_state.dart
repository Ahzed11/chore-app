import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
        final dio = Dio(BaseOptions(
          baseUrl: AppConfig.baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ));
        await dio.post<void>(
          '/auth/logout',
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
  /// Returns `true` on success (new tokens persisted), `false` on failure
  /// (local auth state is cleared via [clearOnUnauthorized]).
  Future<bool> refresh() async {
    final refreshToken = await AuthStorage.getRefreshToken();
    if (refreshToken == null) return false;
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      final response = await dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = response.data!;
      final newAccessToken = data['access_token'] as String;
      await AuthStorage.saveToken(newAccessToken);
      await AuthStorage.saveRefreshToken(data['refresh_token'] as String);
      state = AuthState(status: AuthStatus.authenticated, token: newAccessToken);
      return true;
    } catch (_) {
      await clearOnUnauthorized();
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
