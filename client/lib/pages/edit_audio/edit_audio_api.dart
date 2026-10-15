// edit_audio_api.dart
//
// Endpoints used by EditAudioPage (the whole flow is described in edit_audio_page.dart).
//
// Everything goes through apiCall: it unwraps the `{ status, data }` envelope and never throws.
// A failed call returns an ApiCallFailure and its error was ALREADY shown to the user by
// GlobalErrorInterceptor, so callers must not toast it again. Calls that are handled inline by
// the UI (polling, loading, the title check) are marked silent so they don't toast at all.

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

const kAudioPath = '/api/audio/';
const kIsUploadFinishedPath = '/api/audio/is_upload_finished';
const kAudioInfoPath = '/api/audio/info';
const kIsTitleUniquePath = '/api/audio/is_title_unique';

/// `error_code` the backend answers with (HTTP 400) when a title is already taken.
const kTitleNotUniqueCode = 'TITLE_NOT_UNIQUE';

/// For requests the UI handles inline or that may be cancelled: no error toast.
final _silent = Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true});

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

class AudioUploadApi {
  AudioUploadApi(this._dio);
  final Dio _dio;

  /// Is the queued upload [audioId] processed?
  /// success = finished, queued = still processing, failure = error.
  Future<ApiCallResult<dynamic>> isUploadFinished(String audioId, {CancelToken? cancelToken}) {
    return apiCall<dynamic>(() => _dio.get<dynamic>(kIsUploadFinishedPath, queryParameters: {'audioId': audioId}, cancelToken: cancelToken, options: _silent));
  }

  Future<ApiCallResult<Map<String, dynamic>>> getInfo(String audioId, {CancelToken? cancelToken}) {
    return apiCall<Map<String, dynamic>>(
      () => _dio.get<dynamic>(kAudioInfoPath, queryParameters: {'audioId': audioId}, cancelToken: cancelToken, options: _silent),
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  /// 204 -> success (free). 400 + TITLE_NOT_UNIQUE -> failure with `errorCode == kTitleNotUniqueCode`
  /// (taken). Any other failure means "couldn't verify".
  Future<ApiCallResult<dynamic>> isTitleUnique(String title, {CancelToken? cancelToken}) {
    return apiCall<dynamic>(() => _dio.get<dynamic>(kIsTitleUniquePath, queryParameters: {'title': title}, cancelToken: cancelToken, options: _silent));
  }

  /// Payload: { updates: { audioId, title?, tags? } }
  /// If your backend expects `audioId` NEXT TO `updates` instead, move it here.
  Future<ApiCallResult<dynamic>> update({required String audioId, String? title, Map<String, dynamic>? tags}) {
    return apiCall<dynamic>(
      () => _dio.post<dynamic>(
        kAudioPath,
        data: {
          'updates': {'audioId': audioId, if (title != null) 'title': title, if (tags != null && tags.isNotEmpty) 'tags': tags},
        },
      ),
    );
  }
}

final audioUploadApiProvider = Provider<AudioUploadApi>((ref) => AudioUploadApi(ref.watch(authDioProvider)));
