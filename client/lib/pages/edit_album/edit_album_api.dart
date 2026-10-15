// edit_album_api.dart
//
// Endpoints used by the edit album page, all through apiCall: it unwraps the `{ status, data }`
// envelope and never throws. A failed call returns an ApiCallFailure and its error was ALREADY
// shown to the user by GlobalErrorInterceptor (the load is silent: the page shows it inline).
//
//   GET  /api/album/info?albumId=...                         => data: album
//   POST /api/album/  { name }                                  => data: { id }   (create)
//   POST /api/album/  { updates: { albumId, name? } }
//
// Images:
//   GET / PUT /api/album/avatar/:albumId

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

const kAlbumPath = '/api/album/';
const kAlbumInfoPath = '/api/album/info';

String albumAvatarPath(String albumId) => '/api/album/avatar/$albumId';

/// For requests the page handles inline or that may be cancelled: no error toast.
final _silent = Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true});

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

class AlbumApi {
  AlbumApi(this._dio);
  final Dio _dio;

  Future<ApiCallResult<Map<String, dynamic>>> getInfo(String albumId, {CancelToken? cancelToken}) {
    return apiCall<Map<String, dynamic>>(
      () => _dio.get<dynamic>(kAlbumInfoPath, queryParameters: {'albumId': albumId}, cancelToken: cancelToken, options: _silent),
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  /// Creates an album. The id the server assigned is in `dataOrNull` (see [extractAlbumId]).
  ///
  /// Request:  POST /api/album/  { name }
  /// Response: { status: 'success', data: { id } }
  Future<ApiCallResult<dynamic>> create({required String name}) {
    return apiCall<dynamic>(() => _dio.post<dynamic>(kAlbumPath, data: {'name': name}));
  }

  /// Payload: { updates: { albumId, name? } }
  /// If your backend expects `albumId` NEXT TO `updates` instead, move it here.
  Future<ApiCallResult<dynamic>> update({required String albumId, String? name}) {
    return apiCall<dynamic>(
      () => _dio.post<dynamic>(
        kAlbumPath,
        data: {
          'updates': {'albumId': albumId, if (name != null) 'name': name},
        },
      ),
    );
  }
}

final albumApiProvider = Provider<AlbumApi>((ref) => AlbumApi(ref.watch(authDioProvider)));

/// Finds the id in the `data` of a create response. Accepted: `{ id }`, `{ _id }`, `{ albumId }`
/// or just the id string.
String? extractAlbumId(Object? data) {
  if (data is String && data.isNotEmpty) return data;

  if (data is Map) {
    for (final key in const ['id', '_id', 'albumId']) {
      final value = data[key];
      if (value is String && value.isNotEmpty) return value;
    }
  }
  return null;
}
