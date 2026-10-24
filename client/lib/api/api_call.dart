import 'dart:async';

import 'package:avarim/api/api_error_resolver.dart';
import 'package:avarim/api/api_response.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:dio/dio.dart';
import 'package:avarim/lib/talker.dart';

/// Distinguishes "the call failed" from "the call succeeded and the
/// data happened to be null" (e.g. a 204 No Content response) — a
/// plain `T?` return can't tell these apart, since both would just be
/// `null`. Pattern-match on this instead:
///
///   final result = await apiCall<Map<String, dynamic>>(() => authDio.delete('/api/thing'));
///   switch (result) {
///     case ApiCallSuccess(:final data):
///       // data may itself be null (204) — that's fine, this branch
///       // only runs on genuine success either way.
///     case ApiCallQueued(:final data):
///       // accepted, will be processed later
///     case ApiCallFailure(:final message):
///       // request failed; message is already shown as a toast too.
///   }
sealed class ApiCallResult<T> {
  const ApiCallResult();

  bool get isSuccess => this is ApiCallSuccess<T>;
  bool get isQueued => this is ApiCallQueued<T>;
  bool get isFailure => this is ApiCallFailure<T>;

  /// Convenience for callers that don't care about the failure message,
  /// only whether they got usable data. Returns null for BOTH a failed
  /// call and a successful-but-null one — only use this when that
  /// ambiguity genuinely doesn't matter to the caller; otherwise switch
  /// on the sealed type directly.
  T? get dataOrNull => switch (this) {
    ApiCallSuccess<T>(:final data) => data,
    ApiCallQueued<T>(:final data) => data,
    ApiCallFailure<T>() => null,
  };
}

class ApiCallSuccess<T> extends ApiCallResult<T> {
  final T? data;
  const ApiCallSuccess(this.data);
}

class ApiCallQueued<T> extends ApiCallResult<T> {
  final T? data;
  const ApiCallQueued(this.data);
}

class ApiCallFailure<T> extends ApiCallResult<T> {
  final String message;
  final String? errorCode;

  const ApiCallFailure(this.message, {this.errorCode});
}

/// Call this instead of a raw dio.get/post/etc anywhere you want
/// automatic error-toast handling across every failure shape, plus
/// automatic `data` unwrapping on success.
///
/// Every failure message comes from [ApiErrorResolver], the same place
/// GlobalErrorInterceptor uses, so what the user sees and what
/// `ApiCallFailure.message` holds are always identical.
///
/// Toasts:
///  - DioException: shown by GlobalErrorInterceptor (not here, to avoid
///    two toasts for one failure).
///  - Everything that never reaches the interceptor (a 2xx with a body
///    that isn't our envelope, a failed `fromJson`, any other thrown
///    error): shown here.
///
/// A 204 (or any 2xx with a genuinely empty body) is treated as success
/// with `data: null` directly — it never reaches the envelope parser.
///
/// Success messaging is NOT automatic. Chain `.notifyOnSuccess('...')`
/// onto the request future yourself when you want one:
///
///   final result = await apiCall<void>(
///     () => authDio.post('/api/auth/login', data: {...}).notifyOnSuccess('Welcome back!'),
///   );
///
/// [defaultMessage] replaces the generic "Something went wrong. Please try
/// again." — which is only used for a server 500 without a usable
/// error_code, or for `INTERNAL_ERROR`. It does NOT override timeouts,
/// connection errors, rate limits, other HTTP statuses or specific
/// error_codes. It is applied to both the returned `ApiCallFailure.message`
/// and the interceptor's toast (via a Zone value), so pass a localized string:
///
///   apiCall<void>(() => authDio.post('/api/upload'), defaultMessage: l10n.upload_failed);
Future<ApiCallResult<T>> apiCall<T>(Future<Response> Function() request, {T Function(dynamic data)? fromJson, String? defaultMessage}) async {
  try {
    final response = await (defaultMessage == null ? request() : runZoned(request, zoneValues: {ApiErrorResolver.zoneKey: defaultMessage}));

    talker.debug('api call data: ', response.data);

    final status = response.statusCode;
    final isSuccessStatus = status != null && status >= 200 && status < 300;
    if (isSuccessStatus && (response.data == null || response.data == '')) {
      return ApiCallSuccess<T>(null);
    }

    final parsed = ApiResponse.tryParse(response.data);

    if (parsed is ApiSuccess) return _fromEnvelope<T>(parsed.data, fromJson, queued: false);
    if (parsed is ApiQueued) return _fromEnvelope<T>(parsed.data, fromJson, queued: true);

    final error = ApiErrorResolver.fromResponse(response, defaultMessage: defaultMessage);
    _showError(error.message);
    return ApiCallFailure<T>(error.message, errorCode: error.errorCode);
  } on DioException catch (e) {
    final error = ApiErrorResolver.fromDio(e, defaultMessage: defaultMessage);
    // The toast is already shown by GlobalErrorInterceptor.
    // errorCode lets callers branch on the backend's `error_code` (e.g. TITLE_NOT_UNIQUE).
    return ApiCallFailure<T>(error.message, errorCode: error.errorCode);
  } catch (e) {
    talker.error('apiCall: unexpected error', e);
    final message = ApiErrorResolver.fromUnexpected(e);
    _showError(message);
    return ApiCallFailure<T>(message);
  }
}

/// Builds the success/queued result, running `fromJson` if given.
/// A throwing `fromJson` (or a failed `as T?` cast) is a client-side
/// problem — the request itself worked — so it's reported as an
/// unreadable response rather than a server error.
ApiCallResult<T> _fromEnvelope<T>(dynamic data, T Function(dynamic data)? fromJson, {required bool queued}) {
  try {
    final T? value = (fromJson != null && data != null) ? fromJson(data) : data as T?;
    return queued ? ApiCallQueued<T>(value) : ApiCallSuccess<T>(value);
  } catch (e) {
    talker.error('apiCall: failed to parse response data', e);
    final message = ApiErrorResolver.unexpectedResponse;
    _showError(message);
    return ApiCallFailure<T>(message);
  }
}

void _showError(String message) {
  if (rootContext != null) {
    NotificationService.showError(message: message);
  }
}
