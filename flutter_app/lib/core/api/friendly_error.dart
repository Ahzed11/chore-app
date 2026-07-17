import 'package:dio/dio.dart';

// ---------------------------------------------------------------------------
// friendlyErrorMessage (TASK-062)
// ---------------------------------------------------------------------------

/// Maps [error] to a short, user-facing message safe to show in a snackbar
/// or [AppErrorWidget] — never a raw `DioException.toString()`, which dumps
/// the full request URL and Dio's internal formatting at the user.
///
/// Rules:
///  - connection errors / timeouts → "Can't reach the server…"
///  - HTTP 401 / 403 → a permission message
///  - HTTP 409 / 410 / 422 → the FastAPI `detail` field verbatim when present
///    (automatic 422 request-validation bodies, which carry `detail` as a
///    list of `{loc, msg, type}` objects rather than a string, are flattened
///    into one readable line), else a generic per-status fallback
///  - anything else → a generic message
///
/// Non-[DioException] errors (a thrown `String`, a parsing `FormatException`,
/// etc.) always get the fully generic message — there's no structured body
/// to extract anything useful from.
String friendlyErrorMessage(Object error) {
  if (error is! DioException) {
    return _genericMessage;
  }

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
    case DioExceptionType.transformTimeout:
      // `transformTimeout` (added in dio 5.10) fires when reading/decoding a
      // slow response body times out — from the user's point of view this
      // is the same "couldn't reach the server" story as the other timeouts.
      return _connectionMessage;

    case DioExceptionType.badCertificate:
      // A TLS/certificate mismatch is, from the user's point of view, just
      // another flavor of "couldn't reach the server".
      return _connectionMessage;

    case DioExceptionType.cancel:
      return 'The request was cancelled.';

    case DioExceptionType.badResponse:
      return _messageForResponse(error);

    case DioExceptionType.unknown:
      // Covers things like connection-refused/reset, which on some
      // platforms surface as `unknown` rather than `connectionError`.
      return _connectionMessage;
  }
}

const _connectionMessage =
    "Can't reach the server. Check your connection and try again.";
const _genericMessage = 'Something went wrong. Please try again.';
const _permissionMessage = 'You do not have permission to do that.';

String _messageForResponse(DioException error) {
  final statusCode = error.response?.statusCode;

  if (statusCode == 401 || statusCode == 403) {
    return _permissionMessage;
  }

  if (statusCode == 409 || statusCode == 410 || statusCode == 422) {
    return extractErrorDetail(error) ?? _genericForStatus(statusCode);
  }

  return extractErrorDetail(error) ?? _genericMessage;
}

String _genericForStatus(int? statusCode) {
  switch (statusCode) {
    case 409:
      return 'This conflicts with the current state. Please refresh and try again.';
    case 410:
      return 'This is no longer available.';
    case 422:
      return 'The data submitted was invalid.';
    default:
      return _genericMessage;
  }
}

/// Extracts and flattens a FastAPI-shaped `detail` field from [error]'s
/// response body, or `null` if there isn't a usable one. Exposed publicly
/// (unlike the rest of this file) so call sites that need a custom fallback
/// per error type — e.g. `auth_provider.dart`'s login/register forms, which
/// want "Invalid email or password." rather than the generic message — can
/// reuse the same FastAPI-detail parsing instead of duplicating it.
///
/// FastAPI sends two shapes under `detail`:
///  - a plain string for handwritten `HTTPException`s (e.g. "You are not
///    assigned to this chore") — passed through verbatim.
///  - a list of `{"loc": [...], "msg": "...", "type": "..."}` objects for
///    automatic request-validation (422) errors — flattened into
///    "field: message" lines joined with "; ".
String? extractErrorDetail(DioException error) => _extractDetail(error.response?.data);

String? _extractDetail(Object? responseBody) {
  if (responseBody is! Map) return null;
  final detail = responseBody['detail'];
  if (detail == null) return null;

  if (detail is String) {
    return detail.isEmpty ? null : detail;
  }

  if (detail is List) {
    final messages = detail
        .whereType<Map>()
        .map(_flattenValidationEntry)
        .whereType<String>()
        .toList();
    return messages.isEmpty ? null : messages.join('; ');
  }

  // Unrecognized shape (e.g. a number or nested object) — stringify rather
  // than silently dropping it.
  final asString = detail.toString();
  return asString.isEmpty ? null : asString;
}

/// Flattens a single FastAPI validation-error entry
/// (`{"loc": ["body", "email"], "msg": "field required", "type": "..."}`)
/// into `"email: field required"`. Falls back to just the message when
/// there's no usable `loc`.
String? _flattenValidationEntry(Map entry) {
  final msg = entry['msg']?.toString();
  if (msg == null || msg.isEmpty) return null;

  final loc = entry['loc'];
  if (loc is List && loc.isNotEmpty) {
    // Drop the leading "body"/"query"/"path" location marker — it's
    // implementation detail, not something the user typed.
    final skip = loc.first == 'body' || loc.first == 'query' ? 1 : 0;
    final field = loc.skip(skip).map((e) => e.toString()).join('.');
    if (field.isNotEmpty) return '$field: $msg';
  }

  return msg;
}
