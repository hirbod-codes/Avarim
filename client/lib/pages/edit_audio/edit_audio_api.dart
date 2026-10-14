// edit_audio_api.dart
//
// Endpoints used by EditAudioPage (the whole flow is described in edit_audio_page.dart).

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

const kAudioPath = '/api/audio/';
const kIsUploadFinishedPath = '/api/audio/is_upload_finished';
const kAudioInfoPath = '/api/audio/info';
const kIsTitleUniquePath = '/api/audio/is_title_unique';

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

class AudioUploadApi {
  AudioUploadApi(this._dio);
  final Dio _dio;

  /// Whether the server finished processing the queued upload [audioId].
  /// Throws a [StateError] if the server reports that the job failed.
  Future<bool> isUploadFinished(String audioId, {CancelToken? cancelToken}) async {
    final res = await apiCall(() => _dio.get<dynamic>(kIsUploadFinishedPath, queryParameters: {'audioId': audioId}, cancelToken: cancelToken));

    if (res.isFailure) throw StateError('The server failed to process this upload');

    return res.isSuccess;
  }

  Future<Map<String, dynamic>> getInfo(String audioId, {CancelToken? cancelToken}) async {
    final res = await _dio.get<dynamic>(kAudioInfoPath, queryParameters: {'audioId': audioId}, cancelToken: cancelToken);

    final body = res.data;
    if (body is Map && body['status'] == 'success' && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw StateError('Unexpected response while loading the audio info');
  }

  /// 204 -> free, 400 + TITLE_NOT_UNIQUE -> taken. Anything else throws.
  Future<bool> isTitleUnique(String title, {CancelToken? cancelToken}) async {
    final res = await _dio.get<dynamic>(
      kIsTitleUniquePath,
      queryParameters: {'title': title},
      cancelToken: cancelToken,
      options: Options(validateStatus: (s) => s != null && (s < 300 || s == 400)),
    );

    if (res.statusCode == 400) {
      final data = res.data;
      if (data is Map && data['error_code'] == 'TITLE_NOT_UNIQUE') return false;
      throw StateError('The title check was rejected');
    }
    return true;
  }

  /// Payload: { updates: { audioId, title?, tags? } }
  /// If your backend expects `audioId` NEXT TO `updates` instead, move it here.
  Future<void> update({required String audioId, String? title, Map<String, dynamic>? tags}) async {
    final res = await _dio.post<dynamic>(
      kAudioPath,
      data: {
        'updates': {'audioId': audioId, 'title': ?title, if (tags != null && tags.isNotEmpty) 'tags': tags},
      },
    );

    final body = res.data;
    if (body is Map && body['status'] == 'error') {
      throw StateError(body['message']?.toString() ?? body['error_code']?.toString() ?? 'Update failed');
    }
  }
}

final audioUploadApiProvider = Provider<AudioUploadApi>((ref) => AudioUploadApi(ref.watch(authDioProvider)));
