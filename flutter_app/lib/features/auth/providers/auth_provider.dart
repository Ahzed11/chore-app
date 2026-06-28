import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_state.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class AuthFormState {
  const AuthFormState({
    this.isLoading = false,
    this.errorMessage,
  });

  final bool isLoading;
  final String? errorMessage;

  AuthFormState copyWith({bool? isLoading, String? errorMessage}) {
    return AuthFormState(
      isLoading: isLoading ?? this.isLoading,
      // Passing null explicitly clears the message; use copyWith to reset.
      errorMessage: errorMessage,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class AuthFormNotifier extends Notifier<AuthFormState> {
  @override
  AuthFormState build() => const AuthFormState();

  /// Attempts to log in with [email] and [password].
  ///
  /// On success the token is persisted and `authNotifierProvider` flips to
  /// authenticated, which triggers the router redirect to `/households`.
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true);

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post<Map<String, dynamic>>(
        ApiEndpoints.login,
        data: {
          'email': email,
          'password': password,
        },
      );

      final token = response.data!['access_token'] as String;
      await ref.read(authNotifierProvider.notifier).saveToken(token);

      state = const AuthFormState(); // reset
      return true;
    } on DioException catch (e) {
      final message = _extractMessage(e, fallback: 'Invalid email or password.');
      state = AuthFormState(errorMessage: message);
      return false;
    } catch (_) {
      state = const AuthFormState(errorMessage: 'An unexpected error occurred.');
      return false;
    }
  }

  /// Registers a new account and, on success, logs in automatically.
  Future<bool> register(
    String displayName,
    String email,
    String password,
  ) async {
    state = state.copyWith(isLoading: true);

    try {
      final dio = ref.read(dioProvider);
      await dio.post<Map<String, dynamic>>(
        ApiEndpoints.register,
        data: {
          'display_name': displayName,
          'email': email,
          'password': password,
        },
      );

      // Auto-login after successful registration.
      return login(email, password);
    } on DioException catch (e) {
      final message = _extractMessage(e, fallback: 'Registration failed.');
      state = AuthFormState(errorMessage: message);
      return false;
    } catch (_) {
      state = const AuthFormState(errorMessage: 'An unexpected error occurred.');
      return false;
    }
  }

  /// Clears any displayed error message.
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _extractMessage(DioException e, {required String fallback}) {
    try {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
    } catch (_) {
      // ignore parse errors
    }
    return fallback;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final authFormProvider =
    NotifierProvider<AuthFormNotifier, AuthFormState>(AuthFormNotifier.new);
