import 'dart:convert';

import 'package:chore_app/core/api/api_client.dart';
import 'package:chore_app/features/chores/providers/chores_provider.dart';
import 'package:chore_app/features/household/providers/household_provider.dart';
import 'package:chore_app/features/household/providers/members_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// TASK-059: removeMember / leaveHousehold must invalidate sibling providers
// (chores, members) so assignee names and membership lists don't go stale.
//
// Uses the same FakeAdapter pattern as test/core/api/api_client_test.dart
// and test/features/chores/chores_provider_test.dart.
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

Map<String, dynamic> _memberJson(String userId, {String role = 'member'}) {
  return {
    'user_id': userId,
    'display_name': 'User $userId',
    'role': role,
    'joined_at': '2025-01-01T00:00:00Z',
  };
}

Map<String, dynamic> _choreJson(String id) {
  return {
    'id': id,
    'definition_id': 'def-$id',
    'household_id': 'hh-1',
    'assignee_id': 'user-1',
    'assignee_name': 'Alice',
    'assigned_manually': false,
    'due_date': '2027-01-01T00:00:00Z',
    'status': 'pending',
    'completed_at': null,
    'points_awarded': null,
    'title': 'Chore $id',
    'description': null,
    'category': 'kitchen',
    'effort_level': 'medium',
    'chore_type': 'recurring',
  };
}

void main() {
  test('removeMember invalidates choresNotifierProvider for the household',
      () async {
    var choreFetches = 0;

    final dio = _dio((options) async {
      if (options.path == '/households/hh-1/members' &&
          options.method == 'GET') {
        return _json([_memberJson('user-2')], 200);
      }
      if (options.path == '/households/hh-1/members/user-2' &&
          options.method == 'DELETE') {
        return _json(<String, dynamic>{}, 204);
      }
      if (options.path == '/households/hh-1/chores') {
        choreFetches++;
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
      throw StateError('Unexpected request: ${options.method} ${options.path}');
    });

    final container = ProviderContainer(
      overrides: [dioProvider.overrideWithValue(dio)],
    );
    addTearDown(container.dispose);

    await container.read(choresNotifierProvider('hh-1').future);
    expect(choreFetches, 1);

    // Reading again without a mutation must not refetch.
    await container.read(choresNotifierProvider('hh-1').future);
    expect(choreFetches, 1);

    await container
        .read(membersNotifierProvider('hh-1').notifier)
        .removeMember('user-2');

    // The chores provider must have been invalidated by the removal.
    await container.read(choresNotifierProvider('hh-1').future);
    expect(choreFetches, 2);
  });

  test(
      'leaveHousehold invalidates membersNotifierProvider and '
      'choresNotifierProvider for the household', () async {
    var memberFetches = 0;
    var choreFetches = 0;

    final dio = _dio((options) async {
      if (options.path == '/households' && options.method == 'GET') {
        return _json(<dynamic>[], 200);
      }
      if (options.path == '/households/hh-1/leave' &&
          options.method == 'POST') {
        return _json(<String, dynamic>{}, 204);
      }
      if (options.path == '/households/hh-1/members' &&
          options.method == 'GET') {
        memberFetches++;
        return _json([_memberJson('user-1', role: 'admin')], 200);
      }
      if (options.path == '/households/hh-1/chores') {
        choreFetches++;
        return _json(
          {'items': <dynamic>[], 'total': 0, 'limit': 100, 'offset': 0},
          200,
        );
      }
      throw StateError('Unexpected request: ${options.method} ${options.path}');
    });

    final container = ProviderContainer(
      overrides: [dioProvider.overrideWithValue(dio)],
    );
    addTearDown(container.dispose);

    await container.read(membersNotifierProvider('hh-1').future);
    await container.read(choresNotifierProvider('hh-1').future);
    expect(memberFetches, 1);
    expect(choreFetches, 1);

    await container
        .read(householdsNotifierProvider.notifier)
        .leaveHousehold('hh-1');

    await container.read(membersNotifierProvider('hh-1').future);
    await container.read(choresNotifierProvider('hh-1').future);
    expect(memberFetches, 2);
    expect(choreFetches, 2);
  });
}
