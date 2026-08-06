import 'dart:convert';

import 'package:chore_app/core/api/api_client.dart';
import 'package:chore_app/features/groceries/providers/groceries_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake HttpClientAdapter — routes requests to a caller-supplied responder.
// Mirrors the pattern used in test/features/chores/chores_provider_test.dart.
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
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://test.local',
      // Mirror createDioClient: the JSON content type is what makes Dio's
      // request transformer encode Map bodies before handing them to the
      // adapter.
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );
  dio.httpClientAdapter = _FakeAdapter(responder);
  return dio;
}

Map<String, dynamic> _itemJson(
  String id, {
  String name = 'Milk',
  String? quantity,
  String? notes,
  bool isPurchased = false,
}) {
  return {
    'id': id,
    'household_id': 'hh-1',
    'added_by_id': 'user-1',
    'added_by_name': 'Alice',
    'name': name,
    'quantity': quantity,
    'notes': notes,
    'is_purchased': isPurchased,
    'purchased_by_id': null,
    'purchased_by_name': null,
    'purchased_at': null,
    'created_at': '2026-08-05T10:00:00Z',
  };
}

void main() {
  group('GroceriesNotifier mutations update state directly (TASK-092)', () {
    test('addItem inserts the created item at the front without a re-fetch',
        () async {
      final dio = _dio((options) async {
        if (options.method == 'POST') {
          expect(options.path, '/households/hh-1/groceries');
          // Dio passes the encoded body via requestStream; options.data stays
          // the original Map, so read it directly.
          final body = options.data as Map<String, dynamic>;
          expect(body['name'], 'Bread');
          return _json(_itemJson('i2', name: 'Bread'), 201);
        }
        // Only the initial GET is expected — the mutation must NOT re-fetch.
        expect(options.method, 'GET');
        expect(options.path, '/households/hh-1/groceries');
        return _json([_itemJson('i1')], 200);
      });

      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(groceriesNotifierProvider('hh-1').notifier);
      await container.read(groceriesNotifierProvider('hh-1').future);
      expect(container.read(groceriesNotifierProvider('hh-1')).value, hasLength(1));

      await notifier.addItem('Bread');

      // If addItem re-fetched (the old invalidateSelf path), the responder
      // above would return only [i1] again and this length check would fail.
      final items = container.read(groceriesNotifierProvider('hh-1')).value!;
      expect(items, hasLength(2));
      expect(items.first.name, 'Bread'); // newest first, like the server
    });

    test('updateItem replaces the matching item in place', () async {
      final dio = _dio((options) async {
        if (options.method == 'PATCH') {
          expect(options.path, '/households/hh-1/groceries/i1');
          return _json(
            _itemJson('i1', name: 'Oat Milk', quantity: '2 cartons'),
            200,
          );
        }
        expect(options.method, 'GET');
        return _json([_itemJson('i1')], 200);
      });

      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(groceriesNotifierProvider('hh-1').notifier);
      await container.read(groceriesNotifierProvider('hh-1').future);

      await notifier.updateItem('i1', {
        'name': 'Oat Milk',
        'quantity': '2 cartons',
      });

      final items = container.read(groceriesNotifierProvider('hh-1')).value!;
      expect(items, hasLength(1));
      expect(items.first.name, 'Oat Milk');
      expect(items.first.quantity, '2 cartons');
    });

    test('deleteItem removes the item from the list', () async {
      final dio = _dio((options) async {
        if (options.method == 'DELETE') {
          expect(options.path, '/households/hh-1/groceries/i2');
          return _json('', 204); // 204 No Content
        }
        expect(options.method, 'GET');
        return _json([_itemJson('i1'), _itemJson('i2', name: 'Bread')], 200);
      });

      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(groceriesNotifierProvider('hh-1').notifier);
      await container.read(groceriesNotifierProvider('hh-1').future);
      expect(container.read(groceriesNotifierProvider('hh-1')).value, hasLength(2));

      await notifier.deleteItem('i2');

      final items = container.read(groceriesNotifierProvider('hh-1')).value!;
      expect(items, hasLength(1));
      expect(items.single.name, 'Milk');
    });
  });
}
