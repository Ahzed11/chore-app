import 'dart:convert';

import 'package:chore_app/core/api/api_client.dart';
import 'package:chore_app/features/chores/providers/chores_provider.dart';
import 'package:chore_app/features/leaderboard/providers/leaderboard_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake HttpClientAdapter — routes requests to a caller-supplied responder.
// Mirrors the pattern used in test/core/api/api_client_test.dart.
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

Dio _dio(_ResponderFn responder) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = _FakeAdapter(responder);
  return dio;
}

Map<String, dynamic> _choreJson(
  String id, {
  String status = 'pending',
  int? pointsAwarded,
}) {
  return {
    'id': id,
    'definition_id': 'def-$id',
    'household_id': 'hh-1',
    'assignee_id': 'user-1',
    'assignee_name': 'Alice',
    'assigned_manually': false,
    'due_date': '2027-01-01T00:00:00Z',
    'status': status,
    'completed_at': status == 'complete' ? '2027-01-01T00:00:00Z' : null,
    'points_awarded': pointsAwarded,
    'title': 'Chore $id',
    'description': null,
    'category': 'kitchen',
    'effort_level': 'medium',
    'chore_type': 'recurring',
  };
}

void main() {
  // ---------------------------------------------------------------------------
  // TASK-058: pagination
  // ---------------------------------------------------------------------------

  group('ChoresNotifier pagination (TASK-058)', () {
    test('loops pages with limit=100, increasing offset, until total is reached',
        () async {
      final requestedOffsets = <int>[];

      final dio = _dio((options) async {
        expect(options.path, '/households/hh-1/chores');
        final offset = int.parse(options.queryParameters['offset'] as String);
        final limit = int.parse(options.queryParameters['limit'] as String);
        expect(limit, 100);
        requestedOffsets.add(offset);

        // 120 chores total, split across two pages: 100 then 20.
        if (offset == 0) {
          final items = List.generate(100, (i) => _choreJson('c$i'));
          return _json(
            {'items': items, 'total': 120, 'limit': 100, 'offset': 0},
            200,
          );
        }
        final items = List.generate(20, (i) => _choreJson('c${100 + i}'));
        return _json(
          {'items': items, 'total': 120, 'limit': 100, 'offset': 100},
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final chores =
          await container.read(choresNotifierProvider('hh-1').future);

      expect(chores, hasLength(120));
      // Exactly ceil(120 / 100) = 2 requests.
      expect(requestedOffsets, [0, 100]);
    });

    test('a single page under the limit makes exactly one request', () async {
      var requestCount = 0;

      final dio = _dio((options) async {
        requestCount++;
        final items = List.generate(30, (i) => _choreJson('c$i'));
        return _json(
          {'items': items, 'total': 30, 'limit': 100, 'offset': 0},
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final chores =
          await container.read(choresNotifierProvider('hh-1').future);

      expect(chores, hasLength(30));
      expect(requestCount, 1);
    });

    test('stops at the max-page guard instead of looping forever', () async {
      var requestCount = 0;

      final dio = _dio((options) async {
        requestCount++;
        final offset = int.parse(options.queryParameters['offset'] as String);
        final items = List.generate(100, (i) => _choreJson('c${offset + i}'));
        // A pathological/buggy backend that always claims far more items
        // remain than will ever actually be returned.
        return _json(
          {'items': items, 'total': 1000000, 'limit': 100, 'offset': offset},
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final chores =
          await container.read(choresNotifierProvider('hh-1').future);

      // Guarded at 10 pages of 100 items each rather than spinning forever.
      expect(requestCount, 10);
      expect(chores, hasLength(1000));
    });
  });

  // ---------------------------------------------------------------------------
  // TASK-059: invalidation of related providers after mutations
  // ---------------------------------------------------------------------------

  group('completeChore invalidations (TASK-059)', () {
    test(
        'completing a chore invalidates leaderboardProvider and '
        'weeklyLeaderboardProvider for the same household', () async {
      var leaderboardFetches = 0;

      final dio = _dio((options) async {
        if (options.path == '/households/hh-1/chores') {
          return _json(
            {
              'items': [_choreJson('c1')],
              'total': 1,
              'limit': 100,
              'offset': 0,
            },
            200,
          );
        }
        if (options.path == '/households/hh-1/chores/c1/complete') {
          return _json(_choreJson('c1', status: 'complete', pointsAwarded: 25), 200);
        }
        if (options.path == '/households/hh-1/leaderboard') {
          leaderboardFetches++;
          return _json(
            {
              'entries': <dynamic>[],
              'scope': options.queryParameters['scope'],
              'requesting_user_rank': leaderboardFetches,
            },
            200,
          );
        }
        throw StateError('Unexpected request path: ${options.path}');
      });

      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      // Prime both leaderboard providers.
      await container.read(leaderboardProvider('hh-1').future);
      await container.read(weeklyLeaderboardProvider('hh-1').future);
      expect(leaderboardFetches, 2);

      // Reading again without any mutation must hit the cache, not the
      // network — otherwise the assertion below wouldn't prove anything.
      await container.read(leaderboardProvider('hh-1').future);
      await container.read(weeklyLeaderboardProvider('hh-1').future);
      expect(leaderboardFetches, 2);

      final updated = await container
          .read(choresNotifierProvider('hh-1').notifier)
          .completeChore('c1');

      expect(updated.status, 'complete');
      expect(updated.pointsAwarded, 25);

      // Both leaderboard providers must have been invalidated by the
      // completion, so reading them again triggers a fresh fetch.
      await container.read(leaderboardProvider('hh-1').future);
      await container.read(weeklyLeaderboardProvider('hh-1').future);
      expect(leaderboardFetches, 4);
    });
  });
}
