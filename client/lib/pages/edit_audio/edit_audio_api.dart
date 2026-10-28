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
import 'package:avarim/pages/edit_audio/batch_upload/picked_audio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

const kIsUploadFinishedPath = '/api/audio/is_upload_finished';
const kAudioInfoPath = '/api/audio/info';

// PATCH routes (updates no longer go through `POST /api/audio/`): title and lyrics each have their own;
// every other editable tag goes through /tag. (Artists and albums are links, see audio_links_section.dart.)
// Each answers 204 on success and 400 with an `error_code` (AUDIO_NOT_FOUND, ...) on failure.
// A tag sent as `null` is CLEARED (unset). Absent = unchanged. (The title is required and can't be cleared.)
const kAudioTitlePath = '/api/audio/title';
const kAudioLyricsPath = '/api/audio/lyrics';
const kAudioTagPath = '/api/audio/tag';

// Upload (ASSUMPTION - copy the real values from AudioUploadDialog): multipart POST, the file sent
// under this field name. Answers { status: 'queued', data: { id } }.
const kUploadAudioPath = '/api/audio/';
const kUploadFileField = 'file';

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

  // ── updates (not silent: a failure is toasted by GlobalErrorInterceptor) ───

  /// POST /api/audio/ (multipart) => { status: 'queued', data: { id } }
  ///
  /// success / queued carry `{ id }`; follow it with [isUploadFinished]. Not silent: a failure is toasted by
  /// GlobalErrorInterceptor (the batch upload also shows it on the page).
  Future<ApiCallResult<Map<String, dynamic>>> uploadAudio(PickedAudio audio, {CancelToken? cancelToken, ProgressCallback? onProgress}) {
    return apiCall<Map<String, dynamic>>(() async {
      final form = FormData.fromMap({kUploadFileField: await audio.toMultipart()});
      return _dio.post<dynamic>(kUploadAudioPath, data: form, cancelToken: cancelToken, onSendProgress: onProgress);
    }, fromJson: (data) => Map<String, dynamic>.from(data as Map));
  }

  /// PATCH /api/audio/title  { audioId, title }
  Future<ApiCallResult<dynamic>> updateTitle({required String audioId, required String title}) {
    return _patch(kAudioTitlePath, {'audioId': audioId, 'title': title});
  }

  /// PATCH /api/audio/lyrics  { audioId, lyrics }  (lyrics == null clears them)
  Future<ApiCallResult<dynamic>> updateLyrics({required String audioId, required String? lyrics}) {
    return _patch(kAudioLyricsPath, {'audioId': audioId, 'lyrics': lyrics});
  }

  /// PATCH /api/audio/tag  { audioId, tags }   (a tag with a null value is cleared)
  ///
  /// For every editable tag EXCEPT lyrics. The backend drops `audioTitle` and `lyrics` from this request.
  Future<ApiCallResult<dynamic>> updateTags({required String audioId, required Map<String, dynamic> tags}) {
    return _patch(kAudioTagPath, {'audioId': audioId, 'tags': tags});
  }

  Future<ApiCallResult<dynamic>> _patch(String path, Map<String, dynamic> body) {
    return apiCall<dynamic>(() => _dio.patch<dynamic>(path, data: body));
  }
}

final audioUploadApiProvider = Provider<AudioUploadApi>((ref) => AudioUploadApi(ref.watch(authDioProvider)));
