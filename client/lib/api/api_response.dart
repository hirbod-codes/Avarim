import 'dart:convert';

import 'package:avarim/lib/talker.dart';

/// Mirrors the backend's response envelope:
///
/// ```ts
/// type a = {
///     status: 'success',
///     data: any
/// } | {
///     status: 'error',
///     error_code: string,
/// } | {
///     status: 'error',
///     message: string,
/// } | {
///     status: 'error',
///     messages: string[],
/// }
/// ```
///
/// This is the single place that knows how to read that shape. Everything
/// downstream (the interceptor, any manual call site) works with
/// [ApiResponse] instead of raw JSON.
sealed class ApiResponse {
  const ApiResponse();

  /// Parses a raw response body into the right variant. Returns null if
  /// the body doesn't match any known shape — callers should treat null
  /// as "unrecognized, fall back to a generic message".
  ///
  /// Accepts either an already-decoded Map (the normal case, when Dio's
  /// Content-Type detection worked) or a raw JSON String (fallback, for
  /// when the backend didn't set `Content-Type: application/json` and
  /// Dio left the body undecoded — rather than silently losing the
  /// error_code/message in that case, we decode it ourselves here).
  static ApiResponse? tryParse(dynamic body) {
    var value = body;

    if (value is String) {
      try {
        value = jsonDecode(value);
        talker.info('json decoded value in tryParse method', value);
      } catch (_) {
        return null; // not JSON at all — e.g. an HTML error page from a proxy
      }
    }

    if (value is! Map) return null;

    final status = value['status'];
    if (status == 'success') {
      return ApiSuccess(value['data']);
    }

    if (status == 'queued') {
      return ApiQueued(value['data']);
    }

    if (status == 'error') {
      final errorCode = value['error_code'];
      if (errorCode is String) return ApiErrorCode(errorCode);

      final message = value['message'];
      if (message is String) return ApiErrorMessage(message);

      final messages = value['messages'];
      if (messages is List) {
        return ApiErrorMessages(messages.map((e) => e.toString()).toList());
      }
    }

    return null;
  }
}

class ApiSuccess extends ApiResponse {
  final dynamic data;
  const ApiSuccess(this.data);
}

class ApiQueued extends ApiResponse {
  final dynamic data;
  const ApiQueued(this.data);
}

/// Error identified by a machine-readable code (e.g. `INVALID_OTP`).
/// Needs a lookup table to become user-facing text — see error_code.dart.
class ApiErrorCode extends ApiResponse {
  final String code;
  const ApiErrorCode(this.code);
}

/// Error with a single ready-to-display message from the backend.
class ApiErrorMessage extends ApiResponse {
  final String message;
  const ApiErrorMessage(this.message);
}

/// Error with multiple messages (e.g. several validation failures at once).
class ApiErrorMessages extends ApiResponse {
  final List<String> messages;
  const ApiErrorMessages(this.messages);
}
