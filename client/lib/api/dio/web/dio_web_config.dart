import 'package:dio/dio.dart';

import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config_web.dart' as impl;

/// Configures [dio] for cookie-based auth on web. No-op on mobile/desktop
/// — there's no cookie jar / withCredentials concept there, requests
/// already carry whatever token TokenStorage supplies via AuthInterceptor.
///
/// Call this once, right after creating the Dio instance in
/// dio_providers.dart — not per-request. Reassigning httpClientAdapter
/// on every call (as opposed to once at creation) is wasteful and,
/// worse, easy to mistake for "this must run before every request" when
/// it really only needs to run once for the instance's whole lifetime.
void configureDioForWeb(Dio dio) => impl.configureDioForWeb(dio);
