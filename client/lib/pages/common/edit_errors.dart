// edit_errors.dart
//
// Helper shared by the edit pages. Failed API calls are reported by apiCall and
// GlobalErrorInterceptor (which already show the toast), so only the check for a
// cancelled request is left.

import 'package:dio/dio.dart';

bool isCancel(Object e) => e is DioException && CancelToken.isCancel(e);
