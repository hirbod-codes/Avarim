import 'package:avarim/plan/components/upgrade_dialog.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:dio/dio.dart';

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
class PlanLimitInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler? handler) {
    if ((err.response?.statusCode ?? 500) == 402) {
      if (rootContext != null) {
        showUpgradeDialog(rootContext!);
      }
    }

    handler?.next(err);
  }
}
