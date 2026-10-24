import 'dart:async';

import 'package:avarim/api/api_response.dart';
import 'package:avarim/api/error_codes.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:dio/dio.dart';

class ResolvedApiError {
  final String message;
  final String? errorCode;

  const ResolvedApiError(this.message, {this.errorCode});
}

/// The single place that decides what the user reads when a request fails.
/// Both [GlobalErrorInterceptor] and [apiCall] go through here, so the
/// toast and the `ApiCallFailure.message` can never disagree.
///
/// Resolution order:
///  1. Server-provided info in the body: known `error_code`, `message`,
///     or `messages`.
///  2. What actually happened: timeout, no connection, bad certificate,
///     cancelled, or the HTTP status (401, 403, 404, 413, 429, 502/503...).
///  3. Client-side failures (unparsable response, cast errors, ...).
///
/// The generic "Something went wrong" text is returned ONLY for a server
/// 500 with no usable error_code, or for `INTERNAL_ERROR` / `INTERNAL`.
class ApiErrorResolver {
  const ApiErrorResolver._();

  static AppLocalizations? get _l10n {
    final context = rootContext;
    return context == null ? null : AppLocalizations.of(context);
  }

  // ---------------------------------------------------------------------
  // Entry points
  // ---------------------------------------------------------------------

  /// Zone key used by `apiCall(defaultMessage: ...)` so interceptors that run
  /// inside the call (the error toast) can use the same override.
  static const zoneKey = #apiCallDefaultMessage;

  /// Codes that mean "the server itself failed" — same treatment as a bare 500.
  static const _genericCodes = {'INTERNAL', 'INTERNAL_ERROR'};

  /// A request that threw.
  ///
  /// [defaultMessage] replaces the generic "Something went wrong" text (and
  /// only that text). If null, the value set by `apiCall` in the current
  /// Zone is used, if any.
  static ResolvedApiError fromDio(DioException e, {String? defaultMessage}) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    final parsed = ApiResponse.tryParse(body);

    final message = _fromBody(parsed, body, status, defaultMessage) ?? _fromTransport(e, defaultMessage);
    return ResolvedApiError(message, errorCode: parsed is ApiErrorCode ? parsed.code : null);
  }

  /// A request that returned normally but isn't a usable success
  /// (only reachable if a call site overrides `validateStatus`, or the
  /// server answered 2xx with a body that isn't our envelope).
  static ResolvedApiError fromResponse(Response response, {String? defaultMessage}) {
    final status = response.statusCode;
    final parsed = ApiResponse.tryParse(response.data);
    final isSuccessStatus = status != null && status >= 200 && status < 300;

    final message = _fromBody(parsed, response.data, status, defaultMessage) ?? (isSuccessStatus ? unexpectedResponse : _fromStatus(status, defaultMessage));
    return ResolvedApiError(message, errorCode: parsed is ApiErrorCode ? parsed.code : null);
  }

  /// Anything that isn't a DioException (parse failures, failed casts,
  /// bugs in our own code). These are client-side problems, not the
  /// server's, so they must not read like a server 500.
  static String fromUnexpected(Object error) => error is FormatException || error is TypeError ? unexpectedResponse : clientError;

  // ---------------------------------------------------------------------
  // 1. Server-provided info
  // ---------------------------------------------------------------------

  static String? _fromBody(ApiResponse? parsed, dynamic rawBody, int? status, String? defaultMessage) {
    switch (parsed) {
      case ApiErrorCode(:final code):
        // Unknown codes return null so we fall back to the status-based
        // message instead of hiding everything behind the generic text.
        if (_genericCodes.contains(code)) return _generic(defaultMessage);
        return tryMessageForErrorCode(code);
      case ApiErrorMessage(:final message):
        return message;
      case ApiErrorMessages(:final messages):
        return messages.join('\n');
      case ApiSuccess() || ApiQueued():
        return null;
      case null:
        // Non-enveloped 4xx bodies like `{message: '...'}` or `{error: '...'}`.
        // Skipped for 5xx so raw server internals never reach the user.
        if (rawBody is Map && status != null && status < 500) {
          final fallback = rawBody['message'] ?? rawBody['error'];
          if (fallback is String && fallback.isNotEmpty) return fallback;
        }
        return null;
    }
  }

  // ---------------------------------------------------------------------
  // 2. What actually happened
  // ---------------------------------------------------------------------

  static String _fromTransport(DioException e, String? defaultMessage) => switch (e.type) {
    DioExceptionType.connectionTimeout || DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout => _timeout,
    DioExceptionType.connectionError => _connection,
    DioExceptionType.badCertificate => _badCertificate,
    DioExceptionType.cancel => _cancelled,
    DioExceptionType.badResponse => _fromStatus(e.response?.statusCode, defaultMessage),
    DioExceptionType.unknown => fromUnexpected(e.error ?? e),
    DioExceptionType.transformTimeout => fromUnexpected(e.error ?? e),
  };

  static String _fromStatus(int? status, String? defaultMessage) {
    final l = _l10n;
    return switch (status) {
      400 => l?.error_http_bad_request ?? 'The request was invalid. Please check your input and try again.',
      401 => l?.error_code_unauthorized ?? 'Your session has expired. Please log in again.',
      402 => l?.error_code_feature_not_available ?? 'This feature requires an upgraded plan.',
      403 => l?.error_http_forbidden ?? "You don't have permission to do that.",
      404 => l?.error_http_not_found ?? 'The requested item was not found.',
      408 => _timeout,
      409 => l?.error_http_conflict ?? 'This conflicts with existing data. Refresh and try again.',
      413 => l?.error_http_payload_too_large ?? 'That file or request is too large.',
      415 => l?.error_http_unsupported_media ?? "That file type isn't supported.",
      422 => l?.error_code_invalid_input ?? 'Some of the provided information is invalid.',
      429 => l?.request_rate_limited ?? 'Too many requests. Please wait a moment and try again.',
      500 => _generic(defaultMessage),
      502 || 503 || 504 => l?.request_server_unavailable ?? 'The server is temporarily unavailable. Please try again in a few minutes.',
      _ when status != null && status >= 500 => l?.request_server_error ?? 'The server ran into a problem. Please try again later.',
      _ => clientError,
    };
  }

  // ---------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------

  /// Server 500 without a usable error_code, or INTERNAL_ERROR.
  /// Precedence: explicit override, then the Zone value from `apiCall`,
  /// then the localized default.
  static String _generic(String? defaultMessage) =>
      defaultMessage ?? (Zone.current[zoneKey] as String?) ?? _l10n?.uncaughtError ?? 'Something went wrong. Please try again.';

  static String get _timeout => _l10n?.request_timeout ?? 'The request timed out. Check your connection and try again.';

  static String get _connection => _l10n?.request_connection_error ?? 'Could not reach the server. Check your connection.';

  static String get _cancelled => _l10n?.request_cancelled ?? 'Request cancelled.';

  static String get _badCertificate => _l10n?.request_bad_certificate ?? "Couldn't establish a secure connection to the server.";

  static String get unexpectedResponse =>
      _l10n?.request_unexpected_response ?? "The app couldn't read the server's response. Please update the app or try again.";

  static String get clientError => _l10n?.request_client_error ?? "The request couldn't be completed. Please try again.";
}
