import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio_link.dart';
import 'package:avarim/lib/talker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Page size used when a whole list is fetched.
const _kPageSize = 50;

/// Lookups feed lists and autocompletes: a failure is handled by the caller, so no error toast.
final _silent = Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true});

/// The artist-album-audio relationships (/api/relationship). A row links an audio to an artist and / or an
/// album, both optional. Creating and deleting rows is admin only.
class RelationshipController {
  RelationshipController(this.ref);

  final Ref ref;

  Dio get _dio => ref.read(authDioProvider);

  // ---------------------------------------------------------------------------
  // Reads (GET /api/relationship/..., ?page&pageSize). They throw when a request fails.
  // ---------------------------------------------------------------------------

  /// Artists linked with the audio (with or without an album).
  Future<List<Artist>> artistsOfAudio(String audioId) => _all('/audio/artist', {'audioId': audioId}, Artist.fromJson);

  /// Albums linked with the audio (with or without an artist).
  Future<List<Album>> albumsOfAudio(String audioId) => _all('/audio/album', {'audioId': audioId}, Album.fromJson);

  /// Artists linked with the audio AND the album.
  Future<List<Artist>> artistsOfAudioAlbum(String audioId, String albumId) => _all('/audio/artist/album', {'audioId': audioId, 'albumId': albumId}, Artist.fromJson);

  /// Artists linked with the audio but no album (the audio is one of their singles).
  Future<List<Artist>> artistsOfAudioWithoutAlbum(String audioId) => _all('/audio/artist/album', {'audioId': audioId}, Artist.fromJson);

  /// Albums linked with the audio but no artist.
  Future<List<Album>> albumsOfAudioWithoutArtist(String audioId) => _all('/audio/album/artist', {'audioId': audioId}, Album.fromJson);

  /// Artists linked with the album (an album can have many).
  Future<List<Artist>> artistsOfAlbum(String albumId) => _all('/album/artist', {'albumId': albumId}, Artist.fromJson);

  /// Every pair of the audio: (artist, album), (artist, no album) and (no artist, album).
  Future<List<AudioLink>> linksOfAudio(String audioId) async {
    final (albums, singles, ownerless) = await (albumsOfAudio(audioId), artistsOfAudioWithoutAlbum(audioId), albumsOfAudioWithoutArtist(audioId)).wait;
    final perAlbum = await Future.wait([for (final album in albums) artistsOfAudioAlbum(audioId, album.id)]);

    return [
      for (var i = 0; i < albums.length; i++)
        for (final artist in perAlbum[i]) AudioLink(artist: artist, album: albums[i]),
      for (final album in ownerless) AudioLink(album: album),
      for (final artist in singles) AudioLink(artist: artist),
    ];
  }

  Future<List<T>> _all<T>(String path, Map<String, dynamic> query, T Function(Map<String, dynamic> json) fromJson) async {
    final items = <T>[];
    final seen = <String>{};
    for (var page = 1; ; page++) {
      final res = await apiCall<List<Map<String, dynamic>>>(
        () => _dio.get<dynamic>('/api/relationship$path', queryParameters: {...query, 'page': page, 'pageSize': _kPageSize}, options: _silent),
        fromJson: (data) => [for (final e in List.from(data)) Map<String, dynamic>.from(e as Map)],
      );
      if (res case ApiCallFailure(:final message)) {
        talker.error('GET /api/relationship$path failed: $message');
        throw StateError(message);
      }

      final rows = res.dataOrNull ?? const <Map<String, dynamic>>[];
      var fresh = 0;
      for (final row in rows) {
        if (seen.add(row['_id'].toString())) {
          items.add(fromJson(row));
          fresh++;
        }
      }

      // A short page is the last one. No NEW rows means the server ignored `page`: stop instead of looping.
      if (rows.length < _kPageSize || fresh == 0) return items;
    }
  }

  // ---------------------------------------------------------------------------
  // Writes (admin only). A failure is toasted by the global interceptor; true = success. The server doesn't
  // check that the audio / artist / album exist, so only pass ids of records that do.
  // ---------------------------------------------------------------------------

  /// POST /api/relationship { audioId, artistId?, albumId? }
  Future<bool> create({required String audioId, String? artistId, String? albumId}) async {
    final res = await apiCall<dynamic>(
      () => _dio.post<dynamic>('/api/relationship', data: {'audioId': audioId, if (artistId != null) 'artistId': artistId, if (albumId != null) 'albumId': albumId}),
    );
    return res.isSuccess;
  }

  /// DELETE /api/relationship { audioId, artistId?, albumId? }.
  ///
  /// The server's filter: a field that is left OUT means "none" (rows with no artist / no album), a field sent
  /// as null would mean "any" (it is not filtered), so absent fields are left out of the body on purpose.
  Future<bool> remove({required String audioId, String? artistId, String? albumId}) async {
    final res = await apiCall<dynamic>(
      () => _dio.delete<dynamic>('/api/relationship', data: {'audioId': audioId, if (artistId != null) 'artistId': artistId, if (albumId != null) 'albumId': albumId}),
    );
    return res.isSuccess;
  }

  /// Removes one pair of the audio. [current] is the audio's pairs before the removal.
  ///
  /// A pair with an empty side is deleted by leaving that field out (see [remove]). If the server ignores a
  /// missing field, it deletes every row that matches the other fields, so (artist, no album) also takes that
  /// artist's other pairs along. After the delete the pairs are read again and the ones that should have stayed
  /// are created again.
  Future<bool> removeLink({required String audioId, required AudioLink link, required List<AudioLink> current}) async {
    if (!await remove(audioId: audioId, artistId: link.artist?.id, albumId: link.album?.id)) return false;

    try {
      final after = (await linksOfAudio(audioId)).map((l) => l.key).toSet();
      for (final lost in current.where((l) => l != link && !after.contains(l.key))) {
        await create(audioId: audioId, artistId: lost.artist?.id, albumId: lost.album?.id);
      }
    } catch (e, st) {
      talker.error('could not verify the pairs after a removal', e, st);
    }
    return true;
  }
}

final relationshipControllerProvider = Provider((ref) => RelationshipController(ref));
