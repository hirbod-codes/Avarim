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

  bool _isRefreshing = false;

  bool _isSilent = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler? handler) {
    _isSilent = options.extra[GlobalErrorInterceptor.silentErrorsKey] == true;

    handler?.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final requestOptions = err.requestOptions;

    if (err.response?.statusCode != 401 || requestOptions.path == '/api/auth/refresh') {
      handler.next(err);
      return;
    }

    if (_isRefreshing) {
      handler.next(err);
      return;
    }

    _isRefreshing = true;

    try {
      final refreshToken = await storage.getRefreshToken();

      if (!kIsWeb && refreshToken == null) throw err;

      final response = await refresh(refreshToken, silent: _isSilent);
      if (response == null) {
        await storage.clear();
        await logout(silent: _isSilent);
        handler.next(err);
        return;
      }

      final accessToken = response.accessToken;
      await storage.saveAccessToken(accessToken);

      if (response.refreshToken != null) await storage.saveRefreshToken(response.refreshToken!);

      requestOptions.headers['Authorization'] = 'Bearer $accessToken';

      final retryResponse = await dio.fetch(requestOptions);

      handler.resolve(retryResponse);
    } catch (e) {
      talker.error('error caught in RefreshInterceptor, onError', e);

      handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }
}
