import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/auth/responses/refresh_response.dart';
import 'package:avarim/auth/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/lib/talker.dart';

class RefreshInterceptor extends Interceptor {
  final Dio dio;
  final TokenStorage storage;
  final Ref ref;
  final Future<void> Function({bool silent}) logout;
  final Future<RefreshResponse?> Function(String? refreshToken, {bool silent}) refresh;

  RefreshInterceptor({required this.dio, required this.storage, required this.ref, required this.logout, required this.refresh});

  static const _retriedKey = 'refresh_interceptor_retried';

  /// Shared by all callers that 401 while a refresh is running.
  Future<String?>? _refreshFuture;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final silent = options.extra[GlobalErrorInterceptor.silentErrorsKey] == true;

    if (err.response?.statusCode != 401 || options.path.endsWith('/auth/refresh') || options.extra[_retriedKey] == true) {
      handler.next(err);
      return;
    }

    try {
      final sentAuth = options.headers['Authorization'];
      final currentToken = await storage.getAccessToken();

      String? newToken;
      if (currentToken != null && sentAuth != 'Bearer $currentToken') {
        // Token was already refreshed after this request was sent; just retry.
        newToken = currentToken;
      } else {
        newToken = await _refreshOnce(silent);
      }

      if (newToken == null) {
        handler.next(err);
        return;
      }

      options.headers['Authorization'] = 'Bearer $newToken';
      options.extra[_retriedKey] = true;

      try {
        handler.resolve(await dio.fetch(options));
      } on DioException catch (retryErr) {
        handler.reject(retryErr);
      }
    } catch (e) {
      talker.error('error caught in RefreshInterceptor, onError', e);
      handler.next(err);
    }
  }

  Future<String?> _refreshOnce(bool silent) {
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;

    final future = _doRefresh(silent).whenComplete(() => _refreshFuture = null);
    _refreshFuture = future;
    return future;
  }

  Future<String?> _doRefresh(bool silent) async {
    final refreshToken = await storage.getRefreshToken();
    if (!kIsWeb && refreshToken == null) return null;

    final response = await refresh(refreshToken, silent: silent);
    if (response == null) {
      await storage.clear();
      await logout(silent: silent);
      return null;
    }

    await storage.saveAccessToken(response.accessToken);
    if (response.refreshToken != null) await storage.saveRefreshToken(response.refreshToken!);

    return response.accessToken;
  }
}
