import 'package:avarim/api/api_call_extensions.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/models/auth_models.dart';

/// Which auth methods the backend currently supports, per
/// `/api/auth/supported_auth_methods` → `{ status: 'success', data: ['phone', 'email'] }`.
///
/// autoDispose deliberately: this should never serve a stale answer from
/// a much earlier point in the app's lifetime. Supported methods can
/// change (a feature flag toggling email auth off, say), and a login
/// screen trusting a cached result from the very first cold-start fetch
/// — success or failure — is exactly the kind of bug that's invisible
/// in normal testing and then bites in production. AuthPage additionally
/// invalidates this explicitly on mount (see auth_page.dart) so every
/// visit to /login performs a genuinely fresh check rather than relying
/// on autoDispose's timing alone.
final supportedAuthMethodsProvider = FutureProvider.autoDispose<List<AuthMethod>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/api/auth/supported_auth_methods');
  final data = response.unwrapData<List<dynamic>>();

  return data.map((e) => e.toString()).map(_parseMethod).whereType<AuthMethod>().toList();
});

AuthMethod? _parseMethod(String value) {
  switch (value) {
    case 'email':
      return AuthMethod.email;
    case 'phone':
      return AuthMethod.phone;
    default:
      return null;
  }
}
