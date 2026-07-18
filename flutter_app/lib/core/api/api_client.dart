import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_state.dart';
import '../config/server_url_provider.dart';

// ---------------------------------------------------------------------------
// Dio instance factory
// ---------------------------------------------------------------------------

Dio createDioClient(Ref ref) {
  // Coalesces concurrent refreshes: the first 401 starts the refresh and
  // stores its future here; subsequent 401s await the same future instead
  // of each triggering their own refresh. Reset to null once settled so a
  // later (genuinely new) 401 can refresh again.
  Future<bool>? refreshFuture;

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  // Auth interceptor – sets the current server baseUrl and attaches the
  // Bearer token to every outgoing request, and on 401 performs a single
  // shared refresh then retries the request once.
  //
  // baseUrl is deliberately re-read from serverUrlProvider on every request
  // (via `ref.read`, not baked into BaseOptions at construction) rather than
  // via `ref.watch` on this provider: `RequestOptions.uri` recomputes from
  // `options.baseUrl` + `options.path` on every access (see dio's
  // `options.dart`), so mutating it per-request is enough to pick up a
  // changed server URL immediately. `ref.watch` here would instead rebuild
  // this whole Provider — which invalidates the `ref` captured by these
  // interceptor closures for their remaining lifetime and crashes on the
  // next deferred `ref.read` (Riverpod's "outdated ref" assertion) as soon
  // as serverUrlProvider's initial async load resolves.
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        options.baseUrl = ref.read(serverUrlProvider).url;
        final token = await AuthStorage.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (DioException error, handler) async {
        final requestOptions = error.requestOptions;
        final is401 = error.response?.statusCode == 401;
        // Per-request marker: a request that has already been retried once
        // must never trigger another refresh (prevents infinite loops when
        // the backend persistently 401s after a successful refresh).
        final alreadyRetried = requestOptions.extra['retried'] == true;
        // Auth endpoints (login/register/refresh/logout) must never trigger
        // a refresh — a 401 there is a real credential failure.
        final isAuthPath = requestOptions.path.startsWith('/auth/');

        if (!is401 || alreadyRetried || isAuthPath) {
          return handler.next(error);
        }

        // Join the in-flight refresh, or start a new one if none is running.
        final future = refreshFuture ??=
            ref.read(authNotifierProvider.notifier).refresh();
        bool refreshed;
        try {
          refreshed = await future;
        } catch (_) {
          refreshed = false;
        } finally {
          // Only the request that owns this future clears it, so concurrent
          // waiters don't wipe a newer refresh started after they resumed.
          if (identical(refreshFuture, future)) {
            refreshFuture = null;
          }
        }

        if (!refreshed) {
          return handler.next(error);
        }

        // Retry the original request exactly once with the refreshed token.
        final newToken = await AuthStorage.getToken();
        requestOptions.extra['retried'] = true;
        requestOptions.headers['Authorization'] = 'Bearer $newToken';
        try {
          final retryResponse = await dio.fetch<dynamic>(requestOptions);
          return handler.resolve(retryResponse);
        } on DioException catch (retryError) {
          return handler.next(retryError);
        }
      },
    ),
  );

  return dio;
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final dioProvider = Provider<Dio>((ref) {
  return createDioClient(ref);
});
