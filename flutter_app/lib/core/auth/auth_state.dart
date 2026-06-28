import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ---------------------------------------------------------------------------
// Secure storage helpers
// ---------------------------------------------------------------------------

class AuthStorage {
  AuthStorage._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _tokenKey = 'auth_token';

  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
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
    await AuthStorage.clearToken();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> clearOnUnauthorized() async {
    await AuthStorage.clearToken();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
