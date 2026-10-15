// edit_artist_api.dart
//
// Endpoints used by the edit artist page, all through apiCall: it unwraps the `{ status, data }`
// envelope and never throws. A failed call returns an ApiCallFailure and its error was ALREADY
// shown to the user by GlobalErrorInterceptor (the load is silent: the page shows it inline).
//
//   GET  /api/artist/info?artistId=...                         => data: artist
//   POST /api/artist/  { name }                                  => data: { id }   (create)
//   POST /api/artist/  { updates: { artistId, name? } }
//
// Images:
//   GET / PUT /api/artist/avatar/:artistId
//   GET / PUT /api/artist/banner/:artistId

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

const kArtistPath = '/api/artist/';
const kArtistInfoPath = '/api/artist/info';

String artistAvatarPath(String artistId) => '/api/artist/avatar/$artistId';
String artistBannerPath(String artistId) => '/api/artist/banner/$artistId';

/// For requests the page handles inline or that may be cancelled: no error toast.
final _silent = Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true});

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

class ArtistApi {
  ArtistApi(this._dio);
  final Dio _dio;

  Future<ApiCallResult<Map<String, dynamic>>> getInfo(String artistId, {CancelToken? cancelToken}) {
    return apiCall<Map<String, dynamic>>(
      () => _dio.get<dynamic>(kArtistInfoPath, queryParameters: {'artistId': artistId}, cancelToken: cancelToken, options: _silent),
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  /// Creates an artist. The id the server assigned is in `dataOrNull` (see [extractArtistId]).
  ///
  /// Request:  POST /api/artist/  { name }
  /// Response: { status: 'success', data: { id } }
  Future<ApiCallResult<dynamic>> create({required String name}) {
    return apiCall<dynamic>(() => _dio.post<dynamic>(kArtistPath, data: {'name': name}));
  }

  /// Payload: { updates: { artistId, name? } }
  /// If your backend expects `artistId` NEXT TO `updates` instead, move it here.
  Future<ApiCallResult<dynamic>> update({required String artistId, String? name}) {
    return apiCall<dynamic>(
      () => _dio.post<dynamic>(
        kArtistPath,
        data: {
          'updates': {'artistId': artistId, if (name != null) 'name': name},
        },
      ),
    );
  }
}

final artistApiProvider = Provider<ArtistApi>((ref) => ArtistApi(ref.watch(authDioProvider)));

/// Finds the id in the `data` of a create response. Accepted: `{ id }`, `{ _id }`, `{ artistId }`
/// or just the id string.
String? extractArtistId(Object? data) {
  if (data is String && data.isNotEmpty) return data;

  if (data is Map) {
    for (final key in const ['id', '_id', 'artistId']) {
      final value = data[key];
      if (value is String && value.isNotEmpty) return value;
    }
  }
  return null;
}
