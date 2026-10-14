// edit_errors.dart
//
// Small helpers shared by the edit pages (audio, artist, album).

import 'package:dio/dio.dart';

bool isCancel(Object e) => e is DioException && CancelToken.isCancel(e);

String describeError(Object e) {
  if (e is StateError) return e.message;
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final code = data['error_code'];
      if (code == 'TITLE_NOT_UNIQUE') return 'An audio with this title already exists';
      final message = data['message'] ?? data['error'];
      if (message is String && message.isNotEmpty) return message;
      if (code is String && code.isNotEmpty) return code;
    }
    return e.message ?? 'Request failed';
  }
  return e.toString();
}
