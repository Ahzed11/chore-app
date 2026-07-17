import 'dart:convert';

import 'package:chore_app/core/api/api_client.dart';
import 'package:chore_app/core/auth/auth_state.dart';
import 'package:chore_app/features/household/providers/pending_join_provider.dart';
import 'package:chore_app/main.dart';
import 'package:chore_app/router/app_router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// In-memory fake for flutter_secure_storage (same approach as
// `test/features/server/server_setup_screen_test.dart`: both `AuthStorage`
// and `ServerConfigStorage` share the plugin's single platform channel).
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
// Fake HttpClientAdapter — routes requests to a caller-supplied responder.
// ---------------------------------------------------------------------------

typedef _ResponderFn = Future<ResponseBody> Function(RequestOptions options);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);

  final _ResponderFn responder;

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

ResponseBody _json(Object body, int status) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

const _kToken = 'inviteTok123';

Map<String, dynamic> _householdJson({
  String id = 'hh-99',
  String name = 'The Smiths',
}) {
  return {
    'id': id,
    'name': name,
    'role': 'member',
    'member_count': 3,
    'created_at': '2025-01-01T00:00:00Z',
  };
}

/// Handles every endpoint the join → chore-list flow touches:
///  - `POST /invites/:token/accept` — the join itself
///  - `GET /households` — refetched by `joinByToken`'s `invalidateSelf`
///  - `GET /households/:id/members`, `GET /households/:id/chores` — fetched
///    by `ChoreListScreen`, the screen landed on after a successful join
///  - `POST /auth/login` — only exercised by the logged-out test
_FakeAdapter _buildAdapter({Map<String, dynamic>? household}) {
  final hh = household ?? _householdJson();
  return _FakeAdapter((options) async {
    if (options.path == '/invites/$_kToken/accept' && options.method == 'POST') {
      return _json(hh, 200);
    }
    if (options.path == '/households' && options.method == 'GET') {
      return _json([hh], 200);
    }
    if (options.path.endsWith('/members')) {
      return _json(<dynamic>[], 200);
    }
    if (options.path.endsWith('/chores')) {
      return _json(
        {'items': <dynamic>[], 'total': 0, 'limit': 100, 'offset': 0},
        200,
      );
    }
    if (options.path == '/auth/login' && options.method == 'POST') {
      return _json(
        {'access_token': 'new-access-token', 'refresh_token': 'new-refresh-token'},
        200,
      );
    }
    return _json({'detail': 'not found'}, 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Invite deep link routing (TASK-061) — logged in', () {
    testWidgets(
        'visiting /join/:token while authenticated joins immediately and '
        'lands on the household chore list', (tester) async {
      final storage = FakeSecureStorage()..install();
      addTearDown(storage.uninstall);
      // Simulate an already-configured, already-authenticated install.
      storage.store['server_base_url'] = 'https://chores.example.com';
      storage.store['auth_token'] = 'existing-access-token';
      storage.store['refresh_token'] = 'existing-refresh-token';

      final adapter = _buildAdapter();
      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(
            Dio(BaseOptions())..httpClientAdapter = adapter,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const ChoreApp()),
      );
      await tester.pumpAndSettle();

      // Sanity check: starts authenticated (no login screen).
      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.authenticated,
      );

      // Simulate the OS delivering the `choreapp:///join/:token` intent to
      // the already-running app (or, equivalently, go_router's cold-start
      // resolution of the platform's initial route — see the
      // `_effectiveInitialLocation` note on `InviteResponse.deepLink`).
      container.read(appRouterProvider).go('/join/$_kToken');
      await tester.pumpAndSettle();

      // Joined and redirected straight to the household's chore list — no
      // detour through /login.
      expect(find.byKey(const Key('join_success_snackbar')), findsOneWidget);
      expect(find.text('Successfully joined household!'), findsOneWidget);
      expect(find.text('The Smiths'), findsOneWidget);
      expect(find.byKey(const Key('login_email_field')), findsNothing);
    });
  });

  group('Invite deep link routing (TASK-061) — logged out', () {
    testWidgets(
        'visiting /join/:token while unauthenticated stashes the token, '
        'shows login, and completes the join right after login succeeds',
        (tester) async {
      final storage = FakeSecureStorage()..install();
      addTearDown(storage.uninstall);
      // Server is configured but nobody is logged in yet.
      storage.store['server_base_url'] = 'https://chores.example.com';

      final adapter = _buildAdapter();
      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(
            Dio(BaseOptions())..httpClientAdapter = adapter,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const ChoreApp()),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.unauthenticated,
      );

      container.read(appRouterProvider).go('/join/$_kToken');
      await tester.pumpAndSettle();

      // Bounced to login instead of straight into the join...
      expect(find.byKey(const Key('login_email_field')), findsOneWidget);
      // ...but the token was captured so it isn't lost.
      expect(container.read(pendingJoinTokenProvider), _kToken);

      // Complete login.
      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'alice@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'securePass1',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      // Login success routes straight back through /join/:token, completing
      // the join automatically — the user never has to re-paste the invite.
      expect(find.byKey(const Key('join_success_snackbar')), findsOneWidget);
      expect(find.text('The Smiths'), findsOneWidget);
      // Stash is cleared so a later, unrelated login doesn't replay it.
      expect(container.read(pendingJoinTokenProvider), isNull);
    });

    testWidgets('an expired/invalid invite token shows the existing error '
        'handling and returns to the households list', (tester) async {
      final storage = FakeSecureStorage()..install();
      addTearDown(storage.uninstall);
      storage.store['server_base_url'] = 'https://chores.example.com';
      storage.store['auth_token'] = 'existing-access-token';
      storage.store['refresh_token'] = 'existing-refresh-token';

      final adapter = _FakeAdapter((options) async {
        if (options.path == '/invites/bad-token/accept') {
          return _json({'detail': 'Invite link has expired.'}, 410);
        }
        if (options.path == '/households') {
          return _json(<dynamic>[], 200);
        }
        return _json({'detail': 'not found'}, 404);
      });

      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(
            Dio(BaseOptions())..httpClientAdapter = adapter,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const ChoreApp()),
      );
      await tester.pumpAndSettle();

      container.read(appRouterProvider).go('/join/bad-token');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('join_expired_snackbar')), findsOneWidget);
      expect(
        find.text('Invite link has expired or has already been used.'),
        findsOneWidget,
      );
      // Bounced back to the households list rather than stuck on a blank
      // loading screen.
      expect(find.byKey(const Key('login_email_field')), findsNothing);
    });
  });
}
