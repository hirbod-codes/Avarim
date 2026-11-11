import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/pages/search/music_search/controller/music_search_controller.dart';
import 'package:avarim/pages/search/music_search/models/load_more_mode.dart';
import 'package:avarim/pages/search/music_search/ui/scrollable_list.dart';
import 'package:avarim/pages/search/music_search/ui/search_result_tile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ArtistTopTracks extends ConsumerStatefulWidget {
  const ArtistTopTracks({super.key, required this.artistId});

  final String artistId;

  @override
  ConsumerState<ArtistTopTracks> createState() => _ArtistTopTracks();
}

class _ArtistTopTracks extends ConsumerState<ArtistTopTracks> {
  List<Audio>? _audios;
  bool _loading = true;
  int _page = 0;
  final int _pageSize = 10;
  bool _hasMorePages = true;

  int _pageWhenTracksPlayed = 0;

  StreamSubscription<AudioQueueState>? sub;

  @override
  void initState() {
    super.initState();
    _loadNextPage();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Future<List<Audio>?> _loadNextPage({bool reset = false, int? currentPage}) async {
    if (!_hasMorePages) return null;

    if (currentPage == null) {
      currentPage = _page;
      _page++;
    }

    final res = await apiCall<List<Audio>>(
      () => ref
          .read(authDioProvider)
          .get(
            '/api/top_tracks/',
            queryParameters: Map.from({'artistId': widget.artistId, 'page': currentPage! + 1, 'pageSize': _pageSize}),
            options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
          ),
      fromJson: (data) => List.from(data).map((m) => Audio.fromJson(m)).toList(),
    );
    if (!mounted) return null;

    if (!res.isSuccess) {
      setState(() {
        _loading = false;
      });
      return null;
    }
    final newAudios = res.dataOrNull;

    setState(() {
      if (_audios == null) {
        _audios = newAudios;
      } else {
        _audios?.addAll(newAudios ?? []);
      }

      if (newAudios == null || newAudios.isEmpty) _hasMorePages = false;
      _loading = false;
    });

    return newAudios;
  }

  void _play() {
    if (_audios == null) return;

    _pageWhenTracksPlayed = _page;
    AudioPlayerService.add(audioIds: _audios!.map((m) => m.id).toList());

    sub?.cancel();

    sub = AudioPlayerService.onQueueEnd((state) async {
      try {
        final more = await _loadNextPage(currentPage: _pageWhenTracksPlayed);
        if (more == null) return;

        final fresh = more.where((a) => !state.ids.contains(a.id)).toList();

        if (fresh.isNotEmpty) AudioPlayerService.add(audioIds: fresh.map((m) => m.id).toList());

        _pageWhenTracksPlayed++;
      } catch (err, st) {
        talker.error('caught an exception in an on queue listener', {err, st});

        sub?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final musicSearchState = ref.watch(musicSearchControllerProvider);

    final double h = 300;

    return SizedBox(
      height: _loading || _audios == null || _audios?.isEmpty == true ? 51 : h,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            height: 50,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 10,
              children: [
                Text('Top Tracks', style: theme.textTheme.titleLarge),
                TextButton(
                  onPressed: () {
                    // To do
                  },
                  style: ButtonStyle(foregroundColor: WidgetStatePropertyAll(theme.colorScheme.primary)),
                  child: Row(
                    spacing: 2,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('See All', style: TextStyle(fontSize: 14)),
                      Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _loading
              ? SizedBox(
                  height: h - 51,
                  child: const Center(child: CircularProgressIndicator()),
                )
              : (_audios != null && _audios?.isEmpty != true
                    ? ScrollableList(
                        loadNextPage: ({retryAfterError = false}) {
                          _loadNextPage();
                        },
                        onRefresh: () => _loadNextPage(reset: true),
                        bottomPaddingAbovePlayerDock: 0,
                        loadMoreMode: LoadMoreMode.infiniteScroll,
                        itemCount: _audios!.length,
                        itemBuilder: (context, index) => SearchResultTile(
                          item: _audios![index],
                          isEditModeEnabled: musicSearchState.isEditModeEnabled,
                          isBeingDeleted: musicSearchState.idsBeingDeleted.contains(_audios![index].id),
                          isBeingAddedToQueue: musicSearchState.idsBeingAddedToQueue.contains(_audios![index].id),
                        ),
                      )
                    : SizedBox.shrink()),
        ],
      ),
    );
  }
}
