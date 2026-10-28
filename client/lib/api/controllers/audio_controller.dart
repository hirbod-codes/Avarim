import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/lib/talker.dart';

/// Page size used when all of an audio's artists / albums are fetched.
const _kLinksPageSize = 50;

/// Requests whose failure the UI shows itself (or doesn't care about), so no error toast.
final _silent = Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true});

class AudioController {
  final Ref ref;

  Dio get _authDio => ref.read(authDioProvider);

  AudioController(this.ref);

  Future<Audio?> get({required String audioId}) async {
    talker.info('AudioController.get is called...');

    final response = await apiCall(() => _authDio.get('/api/audio/info?audioId=$audioId'));
    talker.info({'response.dataOrNull': response.dataOrNull});
    if (response.isFailure || response.dataOrNull == null) {
      talker.info('Null response data!');
      talker.info('AudioController.get call ended');
      return null;
    }

    return Audio.fromJson(response.dataOrNull);
  }

  Future<String?> getSignedToken({required String audioId}) async {
    talker.info('AudioController.get is called...');

    final response = await apiCall(() => _authDio.get('/api/audio/singed_token?audioId=$audioId'));
    talker.info({'response.dataOrNull': response.dataOrNull});
    if (response.isFailure || response.dataOrNull == null) {
      talker.info('Null response data!');
      talker.info('AudioController.get call ended');
      return null;
    }

    return response.dataOrNull;
  }

  // ---------------------------------------------------------------------------
  // Artists / albums of an audio. They are not stored on the audio any more, the backend resolves them from
  // the artist-album-audio links: GET /api/audio/artist and GET /api/audio/album (?audioId&page&pageSize).
  // Both throw when a request fails (these are lookups used by lists, so no toast), see audioArtistsProvider.
  // ---------------------------------------------------------------------------

  Future<List<Artist>> artists({required String audioId}) => _listAll<Artist>('/api/audio/artist', audioId, Artist.fromJson);

  Future<List<Album>> albums({required String audioId}) => _listAll<Album>('/api/audio/album', audioId, Album.fromJson);

  Future<List<T>> _listAll<T>(String path, String audioId, T Function(Map<String, dynamic> json) fromJson) async {
    final items = <T>[];
    final seen = <String>{};
    for (var page = 1; ; page++) {
      final res = await apiCall<List<Map<String, dynamic>>>(
        () => _authDio.get<dynamic>(path, queryParameters: {'audioId': audioId, 'page': page, 'pageSize': _kLinksPageSize}, options: _silent),
        fromJson: (data) => [for (final e in List.from(data)) Map<String, dynamic>.from(e as Map)],
      );
      if (res case ApiCallFailure(:final message)) throw StateError(message);

      final rows = res.dataOrNull ?? const <Map<String, dynamic>>[];
      var fresh = 0;
      for (final row in rows) {
        if (seen.add(row['_id'].toString())) {
          items.add(fromJson(row));
          fresh++;
        }
      }

      // A short page is the last one. No NEW rows means the server ignored `page`: stop instead of looping.
      if (rows.length < _kLinksPageSize || fresh == 0) return items;
    }
  }

  // ---------------------------------------------------------------------------
  // Editing the links (admin only). The artist / album must already exist, the client creates them first
  // when needed (see LibraryController). A failure is toasted by the global interceptor; true = success.
  // ---------------------------------------------------------------------------

  /// POST /api/audio/artist { audioId, artistId }: the artist is linked as one of the audio's artists
  /// (without an album, so the audio shows up as one of the artist's singles).
  Future<bool> addArtist({required String audioId, required String artistId}) async {
    final res = await apiCall<dynamic>(() => _authDio.post<dynamic>('/api/audio/artist', data: {'audioId': audioId, 'artistId': artistId}));
    return res.isSuccess;
  }

  /// POST /api/audio/album { audioId, albumId }: the album's own artist (if it has one) is linked with it.
  Future<bool> addAlbum({required String audioId, required String albumId}) async {
    final res = await apiCall<dynamic>(() => _authDio.post<dynamic>('/api/audio/album', data: {'audioId': audioId, 'albumId': albumId}));
    return res.isSuccess;
  }

  /// DELETE /api/audio/artist { audioId, artistId }: removes the artist's own link (the "single" one).
  Future<bool> removeArtist({required String audioId, required String artistId}) async {
    final res = await apiCall<dynamic>(() => _authDio.delete<dynamic>('/api/audio/artist', data: {'audioId': audioId, 'artistId': artistId}));
    return res.isSuccess;
  }

  /// DELETE /api/audio/album { audioId, albumId, artistId? }. [artistId] must be the album's artist (null when
  /// the album has none): that pair is what identifies the link.
  Future<bool> removeAlbum({required String audioId, required String albumId, String? artistId}) async {
    final res = await apiCall<dynamic>(
      () => _authDio.delete<dynamic>('/api/audio/album', data: {'audioId': audioId, 'albumId': albumId, if (artistId != null) 'artistId': artistId}),
    );
    return res.isSuccess;
  }

  /// DELETE /api/audio/:audioId (admin only): deletes the audio itself, so it disappears from every album,
  /// artist and playlist.
  Future<bool> delete({required String audioId}) async {
    final res = await apiCall<dynamic>(() => _authDio.delete<dynamic>('/api/audio/$audioId'));
    return res.isSuccess;
  }
}

final audioControllerProvider = Provider((ref) => AudioController(ref));
