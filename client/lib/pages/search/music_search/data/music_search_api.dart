// API (assumed endpoints - customize)
//
//   GET    {baseUrl}/api/artist?page=1&pageSize=20&search=foo
//   GET    {baseUrl}/api/album?page=1&pageSize=20&search=foo
//   GET    {baseUrl}/api/audio?page=1&pageSize=20&search=foo
//   GET    {baseUrl}/api/playlist?page=1&pageSize=20&search=foo
//   GET    {baseUrl}/api/audio/no_artist?page=1&pageSize=20&search=foo   (the "No artist" tab)
//   GET    {baseUrl}/api/audio/no_album?page=1&pageSize=20&search=foo    (the "Singles" tab)
//   DELETE {baseUrl}/api/audio/:audioId
//   DELETE {baseUrl}/api/artist/:artistId
//   DELETE {baseUrl}/api/album/:albumId
//
// To queue an album / playlist, all of its audios are fetched page by page:
//   GET    {baseUrl}/api/relationship/album/audio?albumId=...&page=1&pageSize=50
//   GET    {baseUrl}/api/playlist/audio?playlistId=...&page=1&pageSize=50
//
// Response: { "items": [ {...}, {...} ] }   (a bare JSON array also works)

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/search_tab.dart';
import '../music_search_config.dart';

/// Requests whose failure the caller words itself (no generic error toast).
final _requestOptionsWithoutErrorToast = Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true});

class MusicSearchApi {
  MusicSearchApi(this._dio);

  final Dio _dio;

  /// One page of results of [tab]. Shows a toast and returns an empty list when the request failed.
  Future<List<WithId>> fetchSearchResultsPage(
    SearchTab tab, {
    required String query,
    required int pageNumber,
    required int pageSize,
    CancelToken? cancelToken,
  }) async {
    final result = await apiCall<List<WithId>>(
      () => _dio.get<dynamic>(
        tab.endpointPath,
        queryParameters: {
          'page': pageNumber,
          'pageSize': pageSize,
          // Omitted when empty so the initial load is a plain "list" request.
          if (query.isNotEmpty) 'search': query,
        },
        cancelToken: cancelToken,
      ),
      fromJson: (data) => List.from(data).map<WithId>((json) => _parseResultItem(tab, json)).toList(),
    );

    if (result.isFailure || result.dataOrNull == null) {
      NotificationService.showError(message: 'Nothing found');
      return [];
    }

    return result.dataOrNull ?? [];
  }

  static WithId _parseResultItem(SearchTab tab, dynamic json) {
    switch (tab) {
      case SearchTab.artists:
        return Artist.fromJson(json);
      case SearchTab.albums:
        return Album.fromJson(json);
      case SearchTab.audios:
      case SearchTab.audiosWithoutArtist:
        return Audio.fromJson(json);
      case SearchTab.audiosWithoutAlbum:
        return Audio.fromJson(json);
      case SearchTab.playlists:
        return Playlist.fromJson(json);
    }
  }

  /// Deletes an audio. Returns true on success.
  Future<bool> deleteAudioById(String audioId) async {
    final result = await apiCall(() => _dio.delete<dynamic>('/api/audio/$audioId'));
    return result.isSuccess;
  }

  /// DELETE /api/artist/:artistId (admin). The server refuses (`UNRESOLVED_ALBUMS_AUDIOS`) while any album or
  /// audio is still linked to the artist. The caller words the failure.
  Future<ApiCallResult<dynamic>> deleteArtistById(String artistId) {
    return apiCall<dynamic>(() => _dio.delete<dynamic>('/api/artist/$artistId', options: _requestOptionsWithoutErrorToast));
  }

  /// DELETE /api/album/:albumId (admin). Only the album goes: its audios stay. The caller words the failure.
  Future<ApiCallResult<dynamic>> deleteAlbumById(String albumId) {
    return apiCall<dynamic>(() => _dio.delete<dynamic>('/api/album/$albumId', options: _requestOptionsWithoutErrorToast));
  }

  /// Ids of every audio of the album [albumId], in order. Null when a request failed
  /// (its error was already shown).
  Future<List<String>?> fetchAllAudioIdsOfAlbum(String albumId) {
    return _fetchAllAudioIdsFromPagedEndpoint('/api/relationship/album/audio', {'albumId': albumId});
  }

  /// Ids of every audio of a playlist, in playlist order. Null when a request failed
  /// (its error was already shown).
  Future<List<String>?> fetchAllAudioIdsOfPlaylist(String playlistId) {
    return _fetchAllAudioIdsFromPagedEndpoint('/api/playlist/audio', {'playlistId': playlistId});
  }

  /// Pages through [endpointPath] until the last page. Both endpoints answer `{ status, data: [audio, ...] }`
  /// (page is 1-based, like the lists above).
  Future<List<String>?> _fetchAllAudioIdsFromPagedEndpoint(String endpointPath, Map<String, dynamic> extraQueryParameters) async {
    final uniqueAudioIds = <String>{}; // a set: keeps the order, drops duplicates

    for (var pageNumber = kFirstPageNumber; ; pageNumber++) {
      final pageResult = await apiCall<List<String>>(
        () => _dio.get<dynamic>(endpointPath, queryParameters: {...extraQueryParameters, 'page': pageNumber, 'pageSize': kQueueAudioIdsFetchPageSize}),
        fromJson: (data) => List.from(data).map(_extractAudioId).whereType<String>().toList(),
      );
      if (pageResult.isFailure) return null;

      final audioIdsOfPage = pageResult.dataOrNull ?? const <String>[];
      final countBeforeAddingPage = uniqueAudioIds.length;
      uniqueAudioIds.addAll(audioIdsOfPage);

      // A short page is the last one. No NEW ids means the server ignored `page`: stop instead of looping forever.
      final isLastPage = audioIdsOfPage.length < kQueueAudioIdsFetchPageSize;
      final serverIgnoredPageParameter = uniqueAudioIds.length == countBeforeAddingPage;
      if (isLastPage || serverIgnoredPageParameter) return uniqueAudioIds.toList();
    }
  }

  /// An audio's id: `_id` (audio documents) or `audioId` (playlist / album link records).
  static String? _extractAudioId(dynamic json) {
    if (json is! Map) return null;
    final audioId = json['_id'] ?? json['audioId'];
    return audioId?.toString();
  }
}

final musicSearchApiProvider = Provider<MusicSearchApi>((ref) => MusicSearchApi(ref.watch(authDioProvider)));
