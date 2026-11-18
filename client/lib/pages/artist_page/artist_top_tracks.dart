import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/components/core/core.dart';
import 'package:avarim/components/core/input/fields/debounced_number_field.dart';
import 'package:avarim/components/core/paged/self_managed_paged_list_view.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/pages/search/edit_mode.dart';
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

  PagedState<Audio> _state = PagedState<Audio>(hasMore: true, isLoadingFirstPage: false, isLoadingNextPage: false);

  PagedState<Audio>? _topTracksPlayState;

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
            '/api/relationship/artist/top_tracks',
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
      child: SelfManagedPagedListView<Audio>(
        loadPage: _loadPage,
        itemBuilder: (context, item, ref) {
          final isEditModeEnabled = ref.watch(editModeProvider);

          return AudioListItem(
            audio: item,
            isEditMode: isEditModeEnabled,
            onDeleted: (String itemId) {
              if (!mounted) return;
              setState(() {
                _state = _state.copyWith(items: _state.items.where((item) => item.id != itemId).toList());
              });
            },
            editActionsLeadings: [_buildTopTrackWeightField(item)],
          );
        },
      ),
    );
  }

  Widget _buildTopTrackWeightField(Audio audio) => RelativeBox(
    width: 80,
    child: DebouncedNumberField(
      hintText: 'Weight',
      initialValue: audio.topTrackWeight,
      disableWhileSaving: true,
      onValueChanged: (value) async {
        final res = await apiCall<List<Audio>>(
          () => ref
              .read(authDioProvider)
              .patch(
                '/api/relationship',
                data: {
                  'filter': {'artistId': widget.artistId, 'audioId': audio.id},
                  'update': {'topTrackWeight': value},
                },
                options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
              ),
        );
        if (!res.isSuccess) {
          throw Error();
        }

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('updated')));
      },
      onError: (error, stackTrace, attemptedValue) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save'))),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final double h = 300;

    // true means this artist doesn't own any audio
    if (_state.items.isEmpty &&
        !_state.isWaitingForFirstPage &&
        !_state.hasError &&
        !_state.hasMore &&
        !_state.isLoadingFirstPage &&
        !_state.isLoadingNextPage) {
      return SizedBox.shrink();
    }

    final isEditModeEnabled = ref.watch(editModeProvider);

    return SizedBox(
      height: h,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        spacing: 5,
        children: [
          SizedBox(
            height: 50,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              spacing: 10,
              children: [
                Row(
                  spacing: 5,
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
          const Divider(),
          Expanded(
            child: SelfManagedPagedListView<Audio>(
              bottomPadding: 0,
              itemPadding: EdgeInsets.all(0),
              state: _state,
              onPagedStateUpdate: (pagedState) {
                if (mounted) {
                  setState(() {
                    _state = pagedState;
                  });
                }
              },
              loadPage: _loadPage,
              itemBuilder: (context, item, _) => AudioListItem(
                audio: item,
                isEditMode: isEditModeEnabled,
                onDeleted: (String itemId) {
                  if (!mounted) return;
                  setState(() {
                    _state = _state.copyWith(items: _state.items.where((item) => item.id != itemId).toList());
                  });
                },
                editActionsLeadings: [_buildTopTrackWeightField(item)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
