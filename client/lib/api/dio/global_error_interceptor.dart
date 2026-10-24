import 'package:avarim/api/api_error_resolver.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:dio/dio.dart';
import 'package:avarim/lib/talker.dart';

/// The single place that shows a failed API request to the user.
/// The wording itself lives in [ApiErrorResolver] so `apiCall` returns
/// exactly the same message that was toasted here.
///
/// Deliberately does NOT show success notifications — see
/// `notifyOnSuccess` in api_call_extensions.dart.
class GlobalErrorInterceptor extends Interceptor {
  /// Requests can opt out of the automatic notification — e.g. a
  /// silent background refresh that wants to handle its own failure
  /// quietly. Set `extra: {'silentErrors': true}` on the RequestOptions.
  static const silentErrorsKey = 'silentErrors';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    talker.error('error caught in GlobalErrorInterceptor', err);

    final silent = err.requestOptions.extra[silentErrorsKey] == true;
    // A cancelled request was cancelled on purpose (screen closed, newer
    // request superseded it) — nothing to tell the user.
    final cancelled = err.type == DioExceptionType.cancel;

    if (!silent && !cancelled && rootContext != null) {
      NotificationService.showError(message: ApiErrorResolver.fromDio(err).message);
    }

    handler.next(err);
  }
}