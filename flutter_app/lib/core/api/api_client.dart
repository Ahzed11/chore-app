import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_state.dart';
import '../config/app_config.dart';

// ---------------------------------------------------------------------------
// Dio instance factory
// ---------------------------------------------------------------------------

Dio createDioClient(Ref ref) {
  // Guards against re-entrancy when a refresh attempt itself returns 401.
  var isRefreshing = false;

  final dio = Dio(
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
        // On 401, attempt a token refresh then retry the original request.
        // The isRefreshing guard prevents infinite retry loops if the
        // refresh endpoint itself returns 401.
        if (error.response?.statusCode == 401 && !isRefreshing) {
          isRefreshing = true;
          try {
            final refreshed =
                await ref.read(authNotifierProvider.notifier).refresh();
            if (refreshed) {
              isRefreshing = false;
              final newToken = await AuthStorage.getToken();
              final opts = error.requestOptions;
              opts.headers['Authorization'] = 'Bearer $newToken';
              final retryResponse = await dio.fetch(opts);
              return handler.resolve(retryResponse);
            } else {
              isRefreshing = false;
              return handler.next(error);
            }
          } catch (_) {
            isRefreshing = false;
            return handler.next(error);
          }
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
