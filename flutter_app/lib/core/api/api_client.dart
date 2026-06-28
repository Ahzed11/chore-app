import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_state.dart';
import '../config/app_config.dart';

// ---------------------------------------------------------------------------
// Dio instance factory
// ---------------------------------------------------------------------------

Dio createDioClient(Ref ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  // Auth interceptor – attaches Bearer token to every outgoing request.
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await AuthStorage.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (DioException error, handler) async {
        // On 401, clear the stored token and set unauthenticated state.
        if (error.response?.statusCode == 401) {
          await AuthStorage.clearToken();
          // Read the notifier via the ref that was captured at creation time.
          ref.read(authNotifierProvider.notifier).clearOnUnauthorized();
        }
        handler.next(error);
      },
    ),
  );

  return dio;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final dioProvider = Provider<Dio>((ref) {
  return createDioClient(ref);
});
