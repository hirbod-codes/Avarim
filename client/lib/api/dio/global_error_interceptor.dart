import 'package:avarim/api/api_response.dart';
import 'package:avarim/api/error_codes.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:avarim/lib/talker.dart';

/// The single place that reads a failed API response and shows the
/// error to the user. Attach this to every Dio instance that talks to
/// your API and no controller/widget needs its own try/catch for
/// "what do I show the user" ever again.
///
/// Deliberately does NOT show success notifications — most successful
/// requests (background refresh, polling, prefetch) shouldn't pop a
/// toast. Success messaging stays an explicit, per-call decision made
/// at the call site (see ApiResult in api_call_extensions.dart) rather
/// than something this interceptor guesses at.
class GlobalErrorInterceptor extends Interceptor {
  /// Requests can opt out of the automatic notification — e.g. a
  /// silent background refresh that wants to handle its own failure
  /// quietly. Set `extra: {'silentErrors': true}` on the RequestOptions.
  static const silentErrorsKey = 'silentErrors';

  @override
  void onError(Exception err, ErrorInterceptorHandler? handler) {
    talker.error('error caught in GlobalErrorInterceptor', err);
    if (err is DioException) {
      final silent = err.requestOptions.extra[silentErrorsKey] == true;
      if (!silent) {
        final message = _messageFor(err);
        final context = rootContext;
        if (context != null) {
          NotificationService.showError(message: message);
        }
      }

      handler?.next(err);
    } else {
      if (rootContext != null) {
        NotificationService.showError(message: AppLocalizations.of(rootContext!)?.uncaughtError ?? 'Something went wrong. Please try again.');
      }
    }
  }

  String _messageFor(DioException err) {
    final parsed = ApiResponse.tryParse(err.response?.data);

    switch (parsed) {
      case ApiErrorCode(:final code):
        return messageForErrorCode(code);
      case ApiErrorMessage(:final message):
        return message;
      case ApiErrorMessages(:final messages):
        return messages.join('\n');
      case ApiSuccess():
        // A 4xx/5xx status with a 'success' body shouldn't happen, but
        // fall through to the generic case rather than assume anything.
        return _genericMessageFor(err);
      case ApiQueued():
        // A 4xx/5xx status with a 'success' body shouldn't happen, but
        // fall through to the generic case rather than assume anything.
        return _genericMessageFor(err);
      case null:
        return _genericMessageFor(err);
    }
  }

  String _genericMessageFor(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return rootContext == null
            ? 'The request timed out. Check your connection and try again.'
            : AppLocalizations.of(rootContext!)?.request_timeout ?? 'The request timed out. Check your connection and try again.';
      case DioExceptionType.connectionError:
        return rootContext == null
            ? 'Could not reach the server. Check your connection.'
            : AppLocalizations.of(rootContext!)?.request_connection_error ?? 'Could not reach the server. Check your connection.';
      case DioExceptionType.cancel:
        return rootContext == null ? 'Request cancelled.' : AppLocalizations.of(rootContext!)?.request_cancelled ?? 'Request cancelled.';
      default:
        return rootContext == null
            ? 'Something went wrong. Please try again.'
            : AppLocalizations.of(rootContext!)?.uncaughtError ?? 'Something went wrong. Please try again.';
    }
  }
}
