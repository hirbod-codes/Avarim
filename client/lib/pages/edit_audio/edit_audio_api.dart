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
const kIsTitleUniquePath = '/api/audio/is_title_unique';

// PATCH routes (updates no longer go through `POST /api/audio/`): title, artists, album and lyrics
// each have their own; every other editable tag goes through /tag.
// Each answers 204 on success and 400 with an `error_code` (AUDIO_NOT_FOUND, TITLE_NOT_UNIQUE, ...) on failure.
const kAudioTitlePath = '/api/audio/title';
const kAudioArtistPath = '/api/audio/artist';
const kAudioAlbumPath = '/api/audio/album';
const kAudioLyricsPath = '/api/audio/lyrics';
const kAudioTagPath = '/api/audio/tag';

// Upload (ASSUMPTION - copy the real values from AudioUploadDialog): multipart POST, the file sent
// under this field name. Answers { status: 'queued', data: { id } }.
const kUploadAudioPath = '/api/audio/';
const kUploadFileField = 'file';

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

  /// PATCH /api/audio/artist  { audioId, artists }
  Future<ApiCallResult<dynamic>> updateArtists({required String audioId, required List<String> artists}) {
    return _patch(kAudioArtistPath, {'audioId': audioId, 'artists': artists});
  }

  /// PATCH /api/audio/album  { audioId, album }
  Future<ApiCallResult<dynamic>> updateAlbum({required String audioId, required String album}) {
    return _patch(kAudioAlbumPath, {'audioId': audioId, 'album': album});
  }

  /// PATCH /api/audio/lyrics  { audioId, lyrics }
  Future<ApiCallResult<dynamic>> updateLyrics({required String audioId, required String lyrics}) {
    return _patch(kAudioLyricsPath, {'audioId': audioId, 'lyrics': lyrics});
  }

  /// PATCH /api/audio/tag  { audioId, tags }
  ///
  /// For every editable tag EXCEPT artists, album and lyrics. The backend drops `audioTitle` and `lyrics`
  /// from this request, and the artist / album routes also keep the artist, album and search data in
  /// sync, so those two must go through their own routes.
  Future<ApiCallResult<dynamic>> updateTags({required String audioId, required Map<String, dynamic> tags}) {
    return _patch(kAudioTagPath, {'audioId': audioId, 'tags': tags});
  }

  Future<ApiCallResult<dynamic>> _patch(String path, Map<String, dynamic> body) {
    return apiCall<dynamic>(() => _dio.patch<dynamic>(path, data: body));
  }
}

final audioUploadApiProvider = Provider<AudioUploadApi>((ref) => AudioUploadApi(ref.watch(authDioProvider)));