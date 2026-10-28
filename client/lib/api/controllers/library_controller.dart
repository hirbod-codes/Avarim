import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Requests whose failure the UI shows itself (or doesn't care about), so no error toast.
final _silent = Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true});

/// Artists and albums: searching them (autocomplete), looking one up and creating one.
class LibraryController {
  LibraryController(this.ref);
  final Ref ref;

  Dio get _dio => ref.read(authDioProvider);

  /// GET /api/artist?search&page&pageSize. Empty on failure (silent: it feeds an autocomplete).
  Future<List<Artist>> searchArtists(String query, {int page = 1, int pageSize = 8, CancelToken? cancelToken}) async {
    final res = await apiCall<List<Artist>>(
      () => _dio.get<dynamic>('/api/artist', queryParameters: {'page': page, 'pageSize': pageSize, 'search': query}, cancelToken: cancelToken, options: _silent),
      fromJson: (data) => [for (final e in List.from(data)) Artist.fromJson(Map<String, dynamic>.from(e as Map))],
    );
    return res.dataOrNull ?? const <Artist>[];
  }

  /// GET /api/album?search&page&pageSize. Empty on failure (silent: it feeds an autocomplete).
  Future<List<Album>> searchAlbums(String query, {int page = 1, int pageSize = 8, CancelToken? cancelToken}) async {
    final res = await apiCall<List<Album>>(
      () => _dio.get<dynamic>('/api/album', queryParameters: {'page': page, 'pageSize': pageSize, 'search': query}, cancelToken: cancelToken, options: _silent),
      fromJson: (data) => [for (final e in List.from(data)) Album.fromJson(Map<String, dynamic>.from(e as Map))],
    );
    return res.dataOrNull ?? const <Album>[];
  }

  /// PATCH /api/album/owner { albumId, newArtistId } (admin only): makes the artist the album's artist. Without
  /// [artistId] the album ends up with no artist. A failure is toasted; true = success.
  Future<bool> setAlbumOwner({required String albumId, String? artistId}) async {
    final res = await apiCall<dynamic>(
      () => _dio.patch<dynamic>('/api/album/owner', data: {'albumId': albumId, if (artistId != null) 'newArtistId': artistId}),
    );
    return res.isSuccess;
  }

  /// GET /api/artist/info?artistId. null when it doesn't exist or the request failed (silent).
  Future<Artist?> artistById(String artistId) async {
    final res = await apiCall<Artist>(
      () => _dio.get<dynamic>('/api/artist/info', queryParameters: {'artistId': artistId}, options: _silent),
      fromJson: (data) => Artist.fromJson(Map<String, dynamic>.from(data as Map)),
    );
    return res.dataOrNull;
  }

  /// GET /api/artist/info?name. null when it doesn't exist or the request failed (silent).
  Future<Artist?> artistByName(String name) async {
    final res = await apiCall<Artist>(
      () => _dio.get<dynamic>('/api/artist/info', queryParameters: {'name': name}, options: _silent),
      fromJson: (data) => Artist.fromJson(Map<String, dynamic>.from(data as Map)),
    );
    return res.dataOrNull;
  }

  /// POST /api/artist?name (admin only). The route answers without the new artist, so it is looked up by its
  /// (unique) name. null when creating failed (a toast says why, e.g. the name is taken).
  Future<Artist?> createArtist(String name) async {
    final created = await apiCall<dynamic>(() => _dio.post<dynamic>('/api/artist', queryParameters: {'name': name}));
    if (created.isFailure) return null;
    return artistByName(name);
  }

  /// POST /api/album?name&artistId (admin only). The route answers `{ albumId }`. [artistId] is optional: an
  /// album belongs to zero or one artist. null when creating failed (a toast says why).
  Future<Album?> createAlbum({required String name, String? artistId}) async {
    final res = await apiCall<String>(
      () => _dio.post<dynamic>('/api/album', queryParameters: {'name': name, if (artistId != null) 'artistId': artistId}),
      fromJson: (data) => (data as Map)['albumId'].toString(),
    );
    final id = res.dataOrNull;
    return id == null ? null : Album(id: id, name: name, artistId: artistId);
  }
}

final libraryControllerProvider = Provider((ref) => LibraryController(ref));
