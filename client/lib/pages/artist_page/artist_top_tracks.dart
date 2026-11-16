import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/components/core/core.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/pages/search/music_search_config.dart';
import 'package:avarim/pages/search/ui/items/audio_list_item.dart';
import 'package:avarim/pages/search/ui/popups/entity_popups.dart';
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

  Future<List<Audio>?> _loadPage(int page) async {
    final res = await apiCall<List<Audio>>(
      () => ref
          .read(authDioProvider)
          .get(
            '/api/top_tracks/',
            queryParameters: Map.from({'artistId': widget.artistId, 'page': page, 'pageSize': kQueuePageSize}),
            options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
          ),
      fromJson: (data) => List.from(data).map((m) => Audio.fromJson(m)).toList(),
    );
    if (!res.isSuccess) {
      return null;
    }
    return res.dataOrNull;
  }

  PagedState<Audio> _state = PagedState<Audio>(hasMore: true, isLoadingFirstPage: true, isLoadingNextPage: false, items: []);

  void _resetPageState() {
    setState(() {
      _state = PagedState<Audio>(isLoadingFirstPage: false, isLoadingNextPage: false, hasMore: true);
    });
  }

  Future<void> _loadNextPage() async {
    if (!_state.hasMore) return;

    setState(() {
      _state = _state.copyWith(isLoadingNextPage: true);
    });

    try {
      final List<Audio>? newAudios = await _loadPage((_state.lastLoadedPage ?? kFirstPageNumber) + 1);
      if (mounted) return;

      setState(() {
        _state = PagedState<Audio>(
          isLoadingFirstPage: false,
          isLoadingNextPage: false,
          error: newAudios != null ? null : Error(),
          lastLoadedPage: (_state.lastLoadedPage ?? kFirstPageNumber) + 1,
          items: [..._state.items, ...(newAudios ?? [])],
          hasMore: newAudios == null ? true : !(newAudios.isEmpty || newAudios.length < kQueuePageSize),
        );
      });
    } catch (err) {
      talker.error('_loadNextPage threw error', err);
    }
  }

  PagedState<Audio>? _topTracksPlayState;

  void _play({bool addAudiosToPlayerQueue = false}) {
    if (_state.items.isEmpty) return;

    _topTracksPlayState = _state.copyWith();
    if (addAudiosToPlayerQueue) {
      AudioPlayerService.add(audioIds: _topTracksPlayState!.items.map((m) => m.id).toList());
    } else {
      AudioPlayerService.replace(audioIds: _topTracksPlayState!.items.map((m) => m.id).toList());
    }

    sub?.cancel();

    sub = AudioPlayerService.onQueueEnd((state) async {
      if (!_topTracksPlayState!.hasMore) return;

      setState(() {
        _topTracksPlayState = _topTracksPlayState!.copyWith(isLoadingNextPage: true);
      });

      try {
        final List<Audio>? newAudios = await _loadPage((_topTracksPlayState!.lastLoadedPage ?? 0) + 1);
        if (!mounted || newAudios == null) return;

        setState(() {
          _topTracksPlayState = PagedState<Audio>(
            isLoadingFirstPage: false,
            isLoadingNextPage: false,
            lastLoadedPage: (_topTracksPlayState!.lastLoadedPage ?? 0) + 1,
            items: [..._topTracksPlayState!.items, ...newAudios],
            hasMore: !(newAudios.isEmpty || newAudios.length < kQueuePageSize),
          );
        });
      } catch (err) {
        talker.error('caught an exception in an on queue listener', {err});
        sub?.cancel();
      }
    });
  }

  Future<void> _showTopTracks() async {
    showEntityPopup(
      leadings: [
        const Icon(Icons.toc_sharp),
        Text('Top Tracks', style: Theme.of(context).textTheme.titleMedium),
      ],
      child: PagedListView(
        state: _state,
        onLoadNext: _loadNextPage,
        onRetryNext: () {
          _loadNextPage();
        },
        onReload: () async {
          _resetPageState();

          _loadNextPage();
        },
        itemBuilder: (context, item) => AudioListItem(
          audio: item,
          isEditMode: true,
          onDeleted: (String itemId) {
            if (!mounted) return;
            setState(() {
              _state = _state.copyWith(items: _state.items.where((item) => item.id != itemId).toList());
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final double h = 300;

    return SizedBox(
      height: _state.items.isEmpty ? 51 : h,
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
                Row(
                  children: [
                    Text('Top Tracks', style: theme.textTheme.titleLarge),
                    TextButton(
                      onPressed: _showTopTracks,
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
                IconButton(onPressed: _play, icon: Icon(Icons.play_arrow)),
              ],
            ),
          ),
          const Divider(height: 1),
          PagedListView(
            state: _state,
            onLoadNext: _loadNextPage,
            onRetryNext: _loadNextPage,
            onReload: _loadNextPage,
            itemBuilder: (context, item) => AudioListItem(
              audio: item,
              isEditMode: true,
              onDeleted: (String itemId) {
                if (!mounted) return;
                setState(() {
                  _state = _state.copyWith(items: _state.items.where((item) => item.id != itemId).toList());
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
