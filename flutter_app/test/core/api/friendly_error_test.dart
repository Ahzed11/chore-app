import 'package:chore_app/core/api/friendly_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DioException _dioError({
  required DioExceptionType type,
  int? statusCode,
  Object? responseData,
}) {
  final requestOptions = RequestOptions(path: '/households/hh-1/chores');
  return DioException(
    requestOptions: requestOptions,
    type: type,
    response: statusCode == null
        ? null
        : Response(
            requestOptions: requestOptions,
            statusCode: statusCode,
            data: responseData,
          ),
  );
}

void main() {
  group('friendlyErrorMessage (TASK-062)', () {
    // -------------------------------------------------------------------
    // Connection / timeout branch
    // -------------------------------------------------------------------

    test('connection timeout maps to "can\'t reach the server"', () {
      final message = friendlyErrorMessage(
        _dioError(type: DioExceptionType.connectionTimeout),
      );
      expect(message, "Can't reach the server. Check your connection and try again.");
    });

    test('send timeout maps to "can\'t reach the server"', () {
      final message =
          friendlyErrorMessage(_dioError(type: DioExceptionType.sendTimeout));
      expect(message, contains("Can't reach the server"));
    });

    test('receive timeout maps to "can\'t reach the server"', () {
      final message = friendlyErrorMessage(
        _dioError(type: DioExceptionType.receiveTimeout),
      );
      expect(message, contains("Can't reach the server"));
    });

    test('connection error maps to "can\'t reach the server"', () {
      final message = friendlyErrorMessage(
        _dioError(type: DioExceptionType.connectionError),
      );
      expect(message, contains("Can't reach the server"));
    });

    test('unknown DioException type also maps to "can\'t reach the server"',
        () {
      final message =
          friendlyErrorMessage(_dioError(type: DioExceptionType.unknown));
      expect(message, contains("Can't reach the server"));
    });

    test('bad certificate maps to "can\'t reach the server"', () {
      final message = friendlyErrorMessage(
        _dioError(type: DioExceptionType.badCertificate),
      );
      expect(message, contains("Can't reach the server"));
    });

    test('cancelled request gets its own message', () {
      final message =
          friendlyErrorMessage(_dioError(type: DioExceptionType.cancel));
      expect(message, 'The request was cancelled.');
    });

    // -------------------------------------------------------------------
    // 401 / 403 → permission message
    // -------------------------------------------------------------------

    test('401 maps to a permission message', () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 401,
        responseData: {'detail': 'Not authenticated'},
      ));
      expect(message, 'You do not have permission to do that.');
    });

    test('403 maps to a permission message, ignoring any detail body', () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 403,
        responseData: {'detail': 'Forbidden'},
      ));
      expect(message, 'You do not have permission to do that.');
    });

    // -------------------------------------------------------------------
    // 409 / 410 / 422 → FastAPI `detail` extraction
    // -------------------------------------------------------------------

    test('409 with a plain string detail passes it through verbatim', () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 409,
        responseData: {'detail': 'You are not assigned to this chore'},
      ));
      expect(message, 'You are not assigned to this chore');
    });

    test('409 with no body falls back to a generic conflict message', () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 409,
      ));
      expect(
        message,
        'This conflicts with the current state. Please refresh and try again.',
      );
    });

    test('410 with a plain string detail passes it through verbatim', () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 410,
        responseData: {'detail': 'Invite link has expired.'},
      ));
      expect(message, 'Invite link has expired.');
    });

    test('410 with no body falls back to a generic "no longer available"',
        () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 410,
      ));
      expect(message, 'This is no longer available.');
    });

    test('422 with a plain string detail passes it through verbatim', () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 422,
        responseData: {'detail': 'Invalid status filter.'},
      ));
      expect(message, 'Invalid status filter.');
    });

    test(
        '422 FastAPI validation-error list body is flattened into readable text',
        () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 422,
        responseData: {
          'detail': [
            {
              'loc': ['body', 'email'],
              'msg': 'field required',
              'type': 'value_error.missing',
            },
            {
              'loc': ['body', 'password'],
              'msg': 'ensure this value has at least 8 characters',
              'type': 'value_error.any_str.min_length',
            },
          ],
        },
      ));
      expect(
        message,
        'email: field required; '
        'password: ensure this value has at least 8 characters',
      );
      // The raw JSON structure must never leak through.
      expect(message, isNot(contains('loc')));
      expect(message, isNot(contains('value_error')));
    });

    test('422 validation entry without a usable loc falls back to just msg',
        () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 422,
        responseData: {
          'detail': [
            {'msg': 'Invalid input', 'type': 'value_error'},
          ],
        },
      ));
      expect(message, 'Invalid input');
    });

    test('422 with an empty body falls back to a generic validation message',
        () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 422,
      ));
      expect(message, 'The data submitted was invalid.');
    });

    // -------------------------------------------------------------------
    // Other status codes
    // -------------------------------------------------------------------

    test('500 with a detail string still surfaces it', () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 500,
        responseData: {'detail': 'Internal server error'},
      ));
      expect(message, 'Internal server error');
    });

    test('500 with no body falls back to the generic message', () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.badResponse,
        statusCode: 500,
      ));
      expect(message, 'Something went wrong. Please try again.');
    });

    // -------------------------------------------------------------------
    // Non-DioException errors
    // -------------------------------------------------------------------

    test('a plain thrown String gets the generic fallback', () {
      final message = friendlyErrorMessage('boom');
      expect(message, 'Something went wrong. Please try again.');
    });

    test('an arbitrary Exception gets the generic fallback', () {
      final message = friendlyErrorMessage(Exception('boom'));
      expect(message, 'Something went wrong. Please try again.');
    });

    // -------------------------------------------------------------------
    // Never leaks raw request/DioException internals
    // -------------------------------------------------------------------

    test('never includes the request path or "DioException" in the message',
        () {
      final message = friendlyErrorMessage(_dioError(
        type: DioExceptionType.connectionTimeout,
      ));
      expect(message, isNot(contains('households/hh-1/chores')));
      expect(message, isNot(contains('DioException')));
    });
  });
}
