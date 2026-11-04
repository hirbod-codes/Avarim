import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../save_to_playlist_config.dart';

/// Requests whose failure the UI shows itself (inline), so no error toast.
final _requestOptionsWithoutErrorToast = Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true});

class SaveToPlaylistApi {
  SaveToPlaylistApi(this._dio);

  final Dio _dio;

  /// Playlists for the picker. A failure was already shown as a toast.
  Future<ApiCallResult<List<Playlist>>> searchPlaylists({required String searchText, required int pageNumber}) {
    return apiCall<List<Playlist>>(
      () => _dio.get<dynamic>(
        '/api/playlist',
        queryParameters: {'page': pageNumber, 'pageSize': kPlaylistPickerPageSize, if (searchText.isNotEmpty) 'search': searchText},
      ),
      fromJson: (data) => List.from(data).map((json) => Playlist.fromJson(json)).toList(),
    );
  }

  /// Ids of every audio of the album [albumId]. Null when a request failed (already shown).
  Future<List<String>?> fetchAllAudioIdsOfAlbum(String albumId) {
    return _fetchAllAudioIdsFromPagedEndpoint('/api/relationship/album/audio', {'albumId': albumId});
  }

  /// Ids of every audio in a playlist. Null when a request failed (already shown).
  Future<List<String>?> fetchAllAudioIdsOfPlaylist(String playlistId) {
    return _fetchAllAudioIdsFromPagedEndpoint('/api/playlist/audio', {'playlistId': playlistId});
  }

  /// Pages through [endpointPath] until the last page (same idea as MusicSearchApi's queue helper).
  Future<List<String>?> _fetchAllAudioIdsFromPagedEndpoint(String endpointPath, Map<String, dynamic> extraQueryParameters) async {
    final uniqueAudioIds = <String>{}; // keeps the order, drops duplicates

    for (var pageNumber = kFirstPageNumber; ; pageNumber++) {
      final pageResult = await apiCall<List<String>>(
        () => _dio.get<dynamic>(
          endpointPath,
          queryParameters: {...extraQueryParameters, 'page': pageNumber, 'pageSize': kAudioIdsFetchPageSize},
        ),
        fromJson: (data) => List.from(data).map(_extractAudioId).whereType<String>().toList(),
      );
      if (pageResult.isFailure) return null;

      final audioIdsOfPage = pageResult.dataOrNull ?? const <String>[];
      final countBeforeAddingPage = uniqueAudioIds.length;
      uniqueAudioIds.addAll(audioIdsOfPage);

      // A short page is the last one. No NEW ids means the server ignored `page`: stop instead of looping forever.
      final isLastPage = audioIdsOfPage.length < kAudioIdsFetchPageSize;
      final serverIgnoredPageParameter = uniqueAudioIds.length == countBeforeAddingPage;
      if (isLastPage || serverIgnoredPageParameter) return uniqueAudioIds.toList();
    }
  }

  static String? _extractAudioId(dynamic json) {
    if (json is! Map) return null;
    return (json['_id'] ?? json['audioId'])?.toString();
  }

  /// POST /api/playlist { name } -> `{ playlistId }` (every user can create playlists; names are unique).
  /// Silent: the caller shows a failure (e.g. "name already taken") inline in the dialog.
  Future<ApiCallResult<String>> createPlaylist(String playlistName) {
    return apiCall<String>(
      () => _dio.post<dynamic>('/api/playlist', data: {'name': playlistName}, options: _requestOptionsWithoutErrorToast),
      fromJson: (data) => (data as Map)['playlistId'].toString(),
    );
  }

  /// Adds audios to a playlist, a chunk per request, stopping at the first failure (already shown).
  /// Returns how many were added.
  Future<int> addAudiosToPlaylist(String playlistId, List<String> audioIds) async {
    var addedCount = 0;

    for (var chunkStartIndex = 0; chunkStartIndex < audioIds.length; chunkStartIndex += kAddAudiosChunkSize) {
      final chunkEndIndex = chunkStartIndex + kAddAudiosChunkSize > audioIds.length ? audioIds.length : chunkStartIndex + kAddAudiosChunkSize;
      final audioIdsChunk = audioIds.sublist(chunkStartIndex, chunkEndIndex);

      final addResult = await apiCall<dynamic>(
        () => _dio.post<dynamic>('/api/playlist/audio', data: {'playlistId': playlistId, 'audioIds': audioIdsChunk}),
      );
      if (addResult.isFailure) break;
      addedCount += audioIdsChunk.length;
    }

    return addedCount;
  }
}

final saveToPlaylistApiProvider = Provider<SaveToPlaylistApi>((ref) => SaveToPlaylistApi(ref.watch(authDioProvider)));
