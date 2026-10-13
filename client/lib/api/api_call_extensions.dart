import 'package:avarim/api/api_response.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:dio/dio.dart';

/// Call-site helpers for the two things that aren't the global
/// interceptor's job: unwrapping the `data` payload from a successful
/// envelope, and showing a success notification when the caller
/// actually wants one (most requests don't — a background refresh or
/// silent prefetch shouldn't pop a toast just because it worked).
extension ApiResponseUnwrap on Response {
  /// Extracts `data` from a `{ status: 'success', data: ... }` envelope.
  /// Throws if the response isn't a success envelope — call this only
  /// after you know the request succeeded (e.g. no DioException was
  /// thrown, since the global interceptor already handles failures).
  T unwrapData<T>() {
    final parsed = ApiResponse.tryParse(data);
    if (parsed is ApiSuccess) return parsed.data as T;
    throw StateError('Expected a success envelope, got: $data');
  }
}

/// Wraps a Dio call so a success toast is shown only when explicitly
/// requested, using the same rootNavigatorKey the error interceptor
/// uses — so call sites don't need a BuildContext either.
///
/// Usage:
///   final content = await dio
///       .post('/api/cards/123/contents', data: {...})
///       .notifyOnSuccess('Successfully added new content.')
///       .then((r) => r.unwrapData<Map<String, dynamic>>());
extension ApiCallNotify on Future<Response> {
  Future<Response> notifyOnSuccess(String message, {Duration? duration}) async {
    final response = await this;
    final context = rootContext;
    if (context != null) {
      NotificationService.showSuccess(message: message, duration: duration);
    }
    return response;
  }
}
