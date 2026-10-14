// edit_artist_api.dart
//
// Endpoints used by the edit artist page:
//
//   GET  /api/artist/info?artistId=...                         => { status: 'success', data: artist }
//   POST /api/artist/  { updates: { artistId, name? } }
//   POST /api/artist/  { name }                                  => { status: 'success', data: { id } }   (create)
//
// Images:
//   GET / PUT /api/artist/avatar/:artistId
//   GET / PUT /api/artist/banner/:artistId

import 'package:avarim/api/dio/dio_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

const kArtistPath = '/api/artist/';
const kArtistInfoPath = '/api/artist/info';

String artistAvatarPath(String artistId) => '/api/artist/avatar/$artistId';
String artistBannerPath(String artistId) => '/api/artist/banner/$artistId';

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

class ArtistApi {
  ArtistApi(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> getInfo(String artistId, {CancelToken? cancelToken}) async {
    final res = await _dio.get<dynamic>(kArtistInfoPath, queryParameters: {'artistId': artistId}, cancelToken: cancelToken);

    final body = res.data;
    if (body is Map && body['status'] == 'success' && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw StateError('Unexpected response while loading the artist');
  }

  /// Creates an artist and returns the id the server assigned to it.
  ///
  /// Request:  POST /api/artist/  { name }
  /// Response: { status: 'success', data: { id } }   (see [_extractId] for the accepted shapes)
  Future<String> create({required String name}) async {
    final res = await _dio.post<dynamic>(kArtistPath, data: {'name': name});

    final body = res.data;
    if (body is Map && body['status'] == 'error') {
      throw StateError(body['message']?.toString() ?? body['error_code']?.toString() ?? 'Could not create the artist');
    }

    final id = _extractId(body);
    if (id == null) throw StateError('The server did not return the id of the new artist');
    return id;
  }

  /// Payload: { updates: { artistId, name? } }
  /// If your backend expects `artistId` NEXT TO `updates` instead, move it here.
  Future<void> update({required String artistId, String? name}) async {
    final res = await _dio.post<dynamic>(
      kArtistPath,
      data: {
        'updates': {'artistId': artistId, if (name != null) 'name': name},
      },
    );

    final body = res.data;
    if (body is Map && body['status'] == 'error') {
      throw StateError(body['message']?.toString() ?? body['error_code']?.toString() ?? 'Update failed');
    }
  }
}

final artistApiProvider = Provider<ArtistApi>((ref) => ArtistApi(ref.watch(authDioProvider)));

/// Finds the id in a create response. Accepted: `{ data: { id } }`, `{ data: { _id } }`,
/// `{ data: { artistId } }`, `{ data: 'the-id' }` or the same keys at the top level.
String? _extractId(Object? body) {
  if (body is! Map) return null;

  final data = body['data'];
  for (final source in <Map>[if (data is Map) data, body]) {
    for (final key in const ['id', '_id', 'artistId']) {
      final value = source[key];
      if (value is String && value.isNotEmpty) return value;
    }
  }
  if (data is String && data.isNotEmpty) return data;
  return null;
}
