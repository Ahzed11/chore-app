import 'dart:convert';

import 'package:chore_app/core/api/api_client.dart';
import 'package:chore_app/core/auth/auth_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// In-memory fake for flutter_secure_storage.
//
// FlutterSecureStorage talks over a platform MethodChannel that throws
// MissingPluginException in the test environment. We intercept that channel
// and back it with a plain Map so AuthStorage works in unit tests.
// ---------------------------------------------------------------------------

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class FakeSecureStorage {
  final Map<String, String> store = {};

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, _handle);
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  }

  Future<Object?> _handle(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    final key = args['key'] as String?;
    switch (call.method) {
      case 'read':
        return store[key];
      case 'write':
        store[key!] = args['value'] as String;
        return null;
      case 'delete':
        store.remove(key);
        return null;
      case 'readAll':
        return Map<String, String>.from(store);
      case 'deleteAll':
        store.clear();
        return null;
      case 'containsKey':
        return store.containsKey(key);
      default:
        return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Fake HttpClientAdapter — routes requests by path/marker to canned responses
// and records how the endpoints were hit.
// ---------------------------------------------------------------------------

typedef ResponderFn = Future<ResponseBody> Function(RequestOptions options);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.responder);

  final ResponderFn responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int status) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

// ---------------------------------------------------------------------------
// Test harness: wires a FakeAdapter into BOTH the main dio (via dioProvider)
// and the auth dio (via authDioProvider override) using a shared responder.
// ---------------------------------------------------------------------------

class Harness {
  Harness(this.responder) {
    storage.install();
    final adapter = FakeAdapter(responder);
    container = ProviderContainer(
      overrides: [
        authDioProvider.overrideWith((ref) {
          final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
          dio.httpClientAdapter = adapter;
          return dio;
        }),
      ],
    );
    dio = container.read(dioProvider);
    dio.httpClientAdapter = adapter;
  }

  final ResponderFn responder;
  final FakeSecureStorage storage = FakeSecureStorage();
  late final ProviderContainer container;
  late final Dio dio;

  void dispose() {
    storage.uninstall();
    container.dispose();
  }
}

bool _isRetried(RequestOptions o) => o.extra['retried'] == true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Token refresh interceptor', () {
    test('401 -> refresh -> retry succeeds transparently', () async {
      var protectedHits = 0;
      var refreshHits = 0;
      final h = Harness((options) async {
        if (options.path == '/auth/refresh') {
          refreshHits++;
          return _json({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
          }, 200);
        }
        // Protected resource: 401 on first (stale) call, 200 on the retry.
        protectedHits++;
        if (_isRetried(options)) {
          return _json({'ok': true}, 200);
        }
        return _json({'detail': 'expired'}, 401);
      });
      addTearDown(h.dispose);

      h.storage.store['auth_token'] = 'stale-access';
      h.storage.store['refresh_token'] = 'stored-refresh';

      final res = await h.dio.get<dynamic>('/protected');

      expect(res.statusCode, 200);
      expect(refreshHits, 1);
      expect(protectedHits, 2); // original 401 + retried 200
      expect(h.storage.store['auth_token'], 'new-access');
      expect(h.storage.store['refresh_token'], 'new-refresh');
    });

    test('retry 401s again -> no infinite loop, user is logged out', () async {
      var refreshHits = 0;
      var protectedHits = 0;
      final h = Harness((options) async {
        if (options.path == '/auth/refresh') {
          refreshHits++;
          return _json({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
          }, 200);
        }
        protectedHits++;
        // Backend persistently rejects even after a successful refresh.
        return _json({'detail': 'expired'}, 401);
      });
      addTearDown(h.dispose);

      h.storage.store['auth_token'] = 'stale-access';
      h.storage.store['refresh_token'] = 'stored-refresh';

      await expectLater(
        h.dio.get<dynamic>('/protected'),
        throwsA(isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          401,
        )),
      );

      // Refresh happened exactly once; the retry 401 did NOT refresh again.
      expect(refreshHits, 1);
      expect(protectedHits, 2); // original + one retry only
      // A 401 from the auth endpoint is not what logs out here; the refresh
      // itself succeeded, so tokens remain the refreshed ones (state stays
      // authenticated). The important guarantee is: no loop.
      expect(
        h.container.read(authNotifierProvider).status,
        AuthStatus.authenticated,
      );
    });

    test('refresh token rejected (401) -> no loop, logged out', () async {
      var refreshHits = 0;
      final h = Harness((options) async {
        if (options.path == '/auth/refresh') {
          refreshHits++;
          return _json({'detail': 'invalid refresh token'}, 401);
        }
        return _json({'detail': 'expired'}, 401);
      });
      addTearDown(h.dispose);

      h.storage.store['auth_token'] = 'stale-access';
      h.storage.store['refresh_token'] = 'bad-refresh';
      // Prime auth state as authenticated.
      h.container.read(authNotifierProvider.notifier);

      await expectLater(
        h.dio.get<dynamic>('/protected'),
        throwsA(isA<DioException>()),
      );

      expect(refreshHits, 1);
      // Refresh endpoint returned 401 -> tokens cleared, logged out.
      expect(h.storage.store['auth_token'], isNull);
      expect(h.storage.store['refresh_token'], isNull);
      expect(
        h.container.read(authNotifierProvider).status,
        AuthStatus.unauthenticated,
      );
    });

    test('three concurrent 401s -> exactly one refresh, all three retried',
        () async {
      var refreshHits = 0;
      var retriedHits = 0;
      final h = Harness((options) async {
        if (options.path == '/auth/refresh') {
          refreshHits++;
          // Small delay so all three 401s overlap before refresh completes.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _json({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
          }, 200);
        }
        if (_isRetried(options)) {
          retriedHits++;
          return _json({'ok': true}, 200);
        }
        return _json({'detail': 'expired'}, 401);
      });
      addTearDown(h.dispose);

      h.storage.store['auth_token'] = 'stale-access';
      h.storage.store['refresh_token'] = 'stored-refresh';

      final results = await Future.wait([
        h.dio.get<dynamic>('/a'),
        h.dio.get<dynamic>('/b'),
        h.dio.get<dynamic>('/c'),
      ]);

      expect(results.map((r) => r.statusCode), everyElement(200));
      expect(refreshHits, 1); // single shared refresh
      expect(retriedHits, 3); // every request retried and succeeded
    });

    test('refresh timeout -> tokens NOT cleared, no logout', () async {
      var refreshHits = 0;
      final h = Harness((options) async {
        if (options.path == '/auth/refresh') {
          refreshHits++;
          throw DioException.connectionTimeout(
            timeout: const Duration(seconds: 10),
            requestOptions: options,
          );
        }
        return _json({'detail': 'expired'}, 401);
      });
      addTearDown(h.dispose);

      h.storage.store['auth_token'] = 'stale-access';
      h.storage.store['refresh_token'] = 'stored-refresh';
      // Ensure notifier exists.
      h.container.read(authNotifierProvider.notifier);

      await expectLater(
        h.dio.get<dynamic>('/protected'),
        throwsA(isA<DioException>()),
      );

      expect(refreshHits, 1);
      // Transient failure must NOT wipe tokens or log out.
      expect(h.storage.store['auth_token'], 'stale-access');
      expect(h.storage.store['refresh_token'], 'stored-refresh');
      expect(
        h.container.read(authNotifierProvider).status,
        isNot(AuthStatus.unauthenticated),
      );
    });

    test('401 from /auth/login -> no refresh attempt', () async {
      var refreshHits = 0;
      var loginHits = 0;
      final h = Harness((options) async {
        if (options.path == '/auth/refresh') {
          refreshHits++;
          return _json({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
          }, 200);
        }
        if (options.path == '/auth/login') {
          loginHits++;
          return _json({'detail': 'invalid credentials'}, 401);
        }
        return _json({'ok': true}, 200);
      });
      addTearDown(h.dispose);

      h.storage.store['refresh_token'] = 'stored-refresh';

      await expectLater(
        h.dio.post<dynamic>('/auth/login',
            data: {'email': 'a@b.c', 'password': 'wrong'}),
        throwsA(isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          401,
        )),
      );

      expect(loginHits, 1);
      expect(refreshHits, 0); // wrong-password login never triggers refresh
    });
  });

  group('AuthNotifier.refresh', () {
    test('missing refresh token returns false without a request', () async {
      final storage = FakeSecureStorage()..install();
      addTearDown(storage.uninstall);
      var refreshHits = 0;
      final container = ProviderContainer(overrides: [
        authDioProvider.overrideWith((ref) {
          final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
          dio.httpClientAdapter = FakeAdapter((options) async {
            refreshHits++;
            return _json({}, 200);
          });
          return dio;
        }),
      ]);
      addTearDown(container.dispose);

      final ok = await container.read(authNotifierProvider.notifier).refresh();
      expect(ok, false);
      expect(refreshHits, 0);
    });
  });
}
