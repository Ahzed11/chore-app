import 'dart:convert';

import 'package:chore_app/core/auth/auth_state.dart';
import 'package:chore_app/core/config/server_config_storage.dart';
import 'package:chore_app/core/config/server_url_provider.dart';
import 'package:chore_app/features/server/screens/server_setup_screen.dart';
import 'package:chore_app/main.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// In-memory fake for flutter_secure_storage (same approach as
// `test/core/api/api_client_test.dart`: FlutterSecureStorage talks over a
// platform MethodChannel that throws MissingPluginException in the test
// environment, so we back the channel with a plain Map).
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
// Fake HttpClientAdapter for the /health probe.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ServerSetupScreen — first run', () {
    testWidgets(
        'fresh install (no stored URL) shows the setup screen before login',
        (tester) async {
      final storage = FakeSecureStorage()..install();
      addTearDown(storage.uninstall);

      await tester.pumpWidget(const ProviderScope(child: ChoreApp()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('server_setup_url_field')), findsOneWidget);
      expect(find.byKey(const Key('server_setup_test_button')), findsOneWidget);
      expect(find.byKey(const Key('login_email_field')), findsNothing);
    });
  });

  group('ServerSetupScreen — connection test', () {
    testWidgets(
        'valid health check saves the URL and proceeds to login',
        (tester) async {
      final storage = FakeSecureStorage()..install();
      addTearDown(storage.uninstall);

      var healthHits = 0;
      final adapter = FakeAdapter((options) async {
        if (options.path.endsWith('/health')) {
          healthHits++;
          return _json({'status': 'ok'}, 200);
        }
        return _json({'detail': 'not found'}, 404);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverProbeDioFactoryProvider.overrideWithValue(
              (baseUrl) => Dio(BaseOptions(baseUrl: baseUrl))
                ..httpClientAdapter = adapter,
            ),
          ],
          child: const ChoreApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Starts on the setup screen (no URL stored yet).
      expect(find.byKey(const Key('server_setup_url_field')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('server_setup_url_field')),
        'https://chores.example.com',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('server_setup_test_button')));
      await tester.pumpAndSettle();

      expect(healthHits, 1);
      expect(storage.store['server_base_url'], 'https://chores.example.com');
      // Router redirect takes over once the server is configured.
      expect(find.byKey(const Key('login_email_field')), findsOneWidget);
      expect(find.byKey(const Key('server_setup_url_field')), findsNothing);
    });

    testWidgets(
        'unreachable server shows an inline error and stays on the screen',
        (tester) async {
      final storage = FakeSecureStorage()..install();
      addTearDown(storage.uninstall);

      final adapter = FakeAdapter((options) async {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection refused',
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverProbeDioFactoryProvider.overrideWithValue(
              (baseUrl) => Dio(BaseOptions(baseUrl: baseUrl))
                ..httpClientAdapter = adapter,
            ),
          ],
          child: const ChoreApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('server_setup_url_field')),
        'https://unreachable.example.com',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('server_setup_test_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('server_setup_error_message')), findsOneWidget);
      expect(find.byKey(const Key('login_email_field')), findsNothing);
      expect(storage.store.containsKey('server_base_url'), isFalse);
    });

    testWidgets(
        'malformed URL shows a validation error without any network call',
        (tester) async {
      final storage = FakeSecureStorage()..install();
      addTearDown(storage.uninstall);

      var probeCalls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverProbeDioFactoryProvider.overrideWithValue((baseUrl) {
              probeCalls++;
              return Dio(BaseOptions(baseUrl: baseUrl));
            }),
          ],
          child: const ChoreApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('server_setup_url_field')),
        'not-a-url',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('server_setup_test_button')));
      await tester.pump();

      expect(
        find.text('Enter a full URL, including http:// or https://.'),
        findsWidgets,
      );
      expect(probeCalls, 0);
      expect(storage.store.containsKey('server_base_url'), isFalse);
    });
  });

  group('ServerSetupScreen — change flow (already configured & logged in)',
      () {
    testWidgets(
        'changing the server logs the user out and persists the new URL',
        (tester) async {
      final storage = FakeSecureStorage()..install();
      addTearDown(storage.uninstall);
      // Simulate an existing install: a server is already configured and
      // the user is logged in.
      storage.store['server_base_url'] = 'https://old.example.com';
      storage.store['auth_token'] = 'existing-access-token';
      storage.store['refresh_token'] = 'existing-refresh-token';

      final adapter = FakeAdapter((options) async => _json({'status': 'ok'}, 200));

      final container = ProviderContainer(
        overrides: [
          serverProbeDioFactoryProvider.overrideWithValue(
            (baseUrl) => Dio(BaseOptions(baseUrl: baseUrl))
              ..httpClientAdapter = adapter,
          ),
        ],
      );
      addTearDown(container.dispose);
      // Prime authNotifierProvider so its async `_initialize()` (reading the
      // stored token) starts now — it's otherwise lazily created only when
      // the screen's submit handler first reads it, which would be too late
      // for the "starts authenticated" sanity check below to observe.
      container.read(authNotifierProvider.notifier);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ServerSetupScreen(canCancel: true)),
        ),
      );
      await tester.pumpAndSettle();

      // Sanity check: starts configured + authenticated.
      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.authenticated,
      );
      expect(
        container.read(serverUrlProvider).url,
        'https://old.example.com',
      );
      expect(find.byKey(const Key('server_setup_cancel_button')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('server_setup_url_field')),
        'https://new.example.com',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('server_setup_test_button')));
      await tester.pumpAndSettle();

      expect(
        container.read(serverUrlProvider).url,
        'https://new.example.com',
      );
      expect(storage.store['server_base_url'], 'https://new.example.com');
      // Tokens are server-specific: switching servers logs the user out.
      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.unauthenticated,
      );
      expect(storage.store.containsKey('auth_token'), isFalse);
      expect(storage.store.containsKey('refresh_token'), isFalse);
    });
  });

  group('ServerUrlValidation.normalize', () {
    test('requires an http/https scheme', () {
      expect(ServerUrlValidation.normalize('example.com'), isNull);
      expect(ServerUrlValidation.normalize('ftp://example.com'), isNull);
      expect(ServerUrlValidation.normalize(''), isNull);
      expect(ServerUrlValidation.normalize('   '), isNull);
    });

    test('accepts http and https URLs', () {
      expect(
        ServerUrlValidation.normalize('http://10.0.2.2:8000'),
        'http://10.0.2.2:8000',
      );
      expect(
        ServerUrlValidation.normalize('https://chores.example.com'),
        'https://chores.example.com',
      );
    });

    test('strips a trailing slash', () {
      expect(
        ServerUrlValidation.normalize('https://chores.example.com/'),
        'https://chores.example.com',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        ServerUrlValidation.normalize('  https://chores.example.com  '),
        'https://chores.example.com',
      );
    });
  });
}
