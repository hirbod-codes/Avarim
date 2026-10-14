// edit_album_api.dart
//
// Endpoints used by the edit album page:
//
//   GET  /api/album/info?albumId=...                         => { status: 'success', data: album }
//   POST /api/album/  { updates: { albumId, name? } }
//   POST /api/album/  { name }                                  => { status: 'success', data: { id } }   (create)
//
// Images:
//   GET / PUT /api/album/avatar/:albumId

import 'package:avarim/api/dio/dio_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

const kAlbumPath = '/api/album/';
const kAlbumInfoPath = '/api/album/info';

String albumAvatarPath(String albumId) => '/api/album/avatar/$albumId';

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

class AlbumApi {
  AlbumApi(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> getInfo(String albumId, {CancelToken? cancelToken}) async {
    final res = await _dio.get<dynamic>(kAlbumInfoPath, queryParameters: {'albumId': albumId}, cancelToken: cancelToken);

    final body = res.data;
    if (body is Map && body['status'] == 'success' && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw StateError('Unexpected response while loading the album');
  }

  /// Creates an album and returns the id the server assigned to it.
  ///
  /// Request:  POST /api/album/  { name }
  /// Response: { status: 'success', data: { id } }   (see [_extractId] for the accepted shapes)
  Future<String> create({required String name}) async {
    final res = await _dio.post<dynamic>(kAlbumPath, data: {'name': name});

    final body = res.data;
    if (body is Map && body['status'] == 'error') {
      throw StateError(body['message']?.toString() ?? body['error_code']?.toString() ?? 'Could not create the album');
    }

    final id = _extractId(body);
    if (id == null) throw StateError('The server did not return the id of the new album');
    return id;
  }

  /// Payload: { updates: { albumId, name? } }
  /// If your backend expects `albumId` NEXT TO `updates` instead, move it here.
  Future<void> update({required String albumId, String? name}) async {
    final res = await _dio.post<dynamic>(
      kAlbumPath,
      data: {
        'updates': {'albumId': albumId, if (name != null) 'name': name},
      },
    );

    final body = res.data;
    if (body is Map && body['status'] == 'error') {
      throw StateError(body['message']?.toString() ?? body['error_code']?.toString() ?? 'Update failed');
    }
  }
}

final albumApiProvider = Provider<AlbumApi>((ref) => AlbumApi(ref.watch(authDioProvider)));

/// Finds the id in a create response. Accepted: `{ data: { id } }`, `{ data: { _id } }`,
/// `{ data: { albumId } }`, `{ data: 'the-id' }` or the same keys at the top level.
String? _extractId(Object? body) {
  if (body is! Map) return null;

  final data = body['data'];
  for (final source in <Map>[if (data is Map) data, body]) {
    for (final key in const ['id', '_id', 'albumId']) {
      final value = source[key];
      if (value is String && value.isNotEmpty) return value;
    }
  }
  if (data is String && data.isNotEmpty) return data;
  return null;
}
