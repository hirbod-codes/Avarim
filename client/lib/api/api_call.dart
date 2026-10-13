import 'package:avarim/api/api_response.dart';
import 'package:avarim/api/error_codes.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/l10n/app_localizations.dart';
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
/// Failure handling covers:
///  1. Non-2xx HTTP, OR a 2xx response whose body isn't a recognized
///     `{status:'success', data:...}` envelope — extracts message/
///     error_code/error from the body if present, generic otherwise.
///  2. Anything else thrown that isn't even a DioException — generic
///     toast, since nothing else in the pipeline would show one.
///
/// A 204 (or any 2xx with a genuinely empty body) is treated as success
/// with `data: null` directly — it never reaches the envelope parser at
/// all, since there's nothing to parse and an empty body would
/// otherwise look identical to a malformed response.
///
/// Success messaging is NOT automatic. Chain `.notifyOnSuccess('...')`
/// onto the request future yourself when you want one:
///
///   final result = await apiCall<void>(
///     () => authDio.post('/api/auth/login', data: {...}).notifyOnSuccess('Welcome back!'),
///   );
///
/// Overlaps with GlobalErrorInterceptor for the non-2xx HTTP case — if
/// you adopt apiCall broadly, consider stripping the toast call out of
/// GlobalErrorInterceptor (keep it for logging only) so a single
/// failure can't show two toasts.
Future<ApiCallResult<T>> apiCall<T>(Future<Response> Function() request, {T Function(dynamic data)? fromJson}) async {
  try {
    final response = await request();

    talker.debug('api call data: ', response.data);
    if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300 && (response.data == null || response.data == '')) {
      return ApiCallSuccess<T>(null);
    }

    final parsed = ApiResponse.tryParse(response.data);
    talker.debug('api call data: ', parsed);

    if (parsed is ApiSuccess) {
      ApiCallSuccess<T> result;
      if (fromJson != null && parsed.data != null) {
        try {
          result = ApiCallSuccess<T>(fromJson(parsed.data));
        } catch (e) {
          talker.error('apiCall, failed parse data, error caught in apiCall method', e);
          String message = rootContext == null ? 'Something went wrong.' : AppLocalizations.of(rootContext!)!.uncaughtError;
          return ApiCallFailure(message);
        }
      } else {
        result = ApiCallSuccess<T>(parsed.data as T?);
      }
      return result;
    }

    if (parsed is ApiQueued) {
      ApiCallQueued<T> result;
      if (fromJson != null && parsed.data != null) {
        try {
          result = ApiCallQueued<T>(fromJson(parsed.data));
        } catch (e) {
          talker.error('apiCall, failed parse data, error caught in apiCall method', e);
          String message = rootContext == null ? 'Something went wrong.' : AppLocalizations.of(rootContext!)!.uncaughtError;
          return ApiCallFailure(message);
        }
      } else {
        result = ApiCallQueued<T>(parsed.data as T?);
      }
      return result;
    }

    final message = _extractMessage(parsed, response.data, url: response.requestOptions.path);
    _showError(message);
    return ApiCallFailure<T>(message, errorCode: parsed is ApiErrorCode ? parsed.code : null);
  } on DioException catch (e) {
    final message = _extractMessage(ApiResponse.tryParse(e.response?.data), e.response?.data, url: e.response?.requestOptions.path);
    // message is already shown by dio GlobalErrorInterceptor
    // _showError(message);
    return ApiCallFailure<T>(message);
  } catch (e) {
    talker.error('apiCall: unexpected error', e);
    String message = rootContext == null ? 'Something went wrong.' : AppLocalizations.of(rootContext!)!.uncaughtError;
    _showError(message);
    return ApiCallFailure<T>(message);
  }
}

String _extractMessage(ApiResponse? parsed, dynamic rawBody, {String? url}) {
  switch (parsed) {
    case ApiErrorCode(:final code):
      return messageForErrorCode(code);
    case ApiErrorMessage(:final message):
      return message;
    case ApiErrorMessages(:final messages):
      return messages.join('\n');
    default:
      if (rawBody is Map) {
        final fallback = rawBody['message'] ?? rawBody['error'];
        if (fallback is String && fallback.isNotEmpty) return fallback;
      }
      return 'Something went wrong.';
  }
}

void _showError(String message) {
  final context = rootContext;
  if (context != null) {
    NotificationService.showError(message: message);
  }
}
