import 'dart:async';

import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/app_config.dart';
import 'package:avarim/components/contents/audio_row_actions.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/components/popup.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/pages/edit_album/edit_album_page.dart';
import 'package:avarim/pages/edit_artist/edit_artist_page.dart';
import 'package:avarim/pages/edit_audio/edit_audio_page.dart';
import 'package:avarim/pages/search/music_search/controller/music_search_controller.dart';
import 'package:avarim/pages/search/music_search/data/music_search_api.dart';
import 'package:avarim/pages/search/music_search/models/load_more_mode.dart';
import 'package:avarim/pages/search/music_search/music_search_config.dart';
import 'package:avarim/pages/search/music_search/ui/delete_confirmation_dialog.dart';
import 'package:avarim/pages/search/music_search/ui/scrollable_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'artists_subtitles.dart';
import 'authenticated_thumbnail.dart';

/// One row of the results: an artist, an album, an audio or a playlist.
class SearchResultTile extends ConsumerStatefulWidget {
  const SearchResultTile({
    super.key,
    required this.item,
    this.onTap,
    required this.isEditModeEnabled,
    required this.isBeingDeleted,
    required this.isBeingAddedToQueue,
    this.onEdit,
    this.onDelete,
    this.onAddToQueue,
    this.onAvatarPlay,
  });

  final WithId item;
  final VoidCallback? onTap;

  /// Shows edit / delete buttons instead of the usual trailing widgets.
  final bool isEditModeEnabled;

  /// This item's delete request is in flight.
  final bool isBeingDeleted;

  /// This album's / playlist's audios are being fetched to be queued.
  final bool isBeingAddedToQueue;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Albums and playlists: appends all their audios to the player queue.
  final VoidCallback? onAddToQueue;

  /// Albums and playlists: replaces all of the player queue with their audios.
  final VoidCallback? onAvatarPlay;

  @override
  ConsumerState<SearchResultTile> createState() => _SearchResultTile();
}

class _SearchResultTile extends ConsumerState<SearchResultTile> {
  /// Narrower screens only have room for the audio's buttons, not for its duration.
  static const _minimumScreenWidthToShowAudioDuration = 480;

  ListTile _getAudioTile(Audio audio, bool isPlaying) {
    return ListTile(
      onTap: widget.isBeingDeleted ? null : _onTap,
      selected: isPlaying,
      leading: AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/audio/coverArt/${audio.id}', placeholderIcon: Icons.music_note),
      title: _buildSingleLineText(audio.title),
      // an audio's artists are resolved from its links (they aren't part of the audio document)
      subtitle: AudioArtistsSubtitle(audioId: audio.id),
      trailing: widget.isEditModeEnabled ? _buildEditModeActions(context) : _buildAudioTrailing(context, audio),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioQueueState>(
      valueListenable: AudioPlayerService.queue,
      builder: (context, queue, _) {
        return switch (widget.item) {
          Artist artist => ListTile(
            onTap: _onTap,
            leading: AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/artist/avatar/${artist.id}', placeholderIcon: Icons.person, isCircular: true),
            title: _buildSingleLineText(artist.name),
            trailing: widget.isEditModeEnabled ? _buildEditModeActions(context) : null,
          ),
          Album album => ListTile(
            onTap: _onTap,
            leading: FittedBox(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: 5,
                children: [
                  if (widget.onAvatarPlay != null) IconButton(tooltip: 'Play', icon: const Icon(Icons.play_arrow), onPressed: widget.onAvatarPlay),
                  AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/album/avatar/${album.id}', placeholderIcon: Icons.album),
                ],
              ),
            ),
            title: _buildSingleLineText(album.name),
            subtitle: AlbumArtistsSubtitle(albumId: album.id),
            trailing: widget.isEditModeEnabled ? _buildEditModeActions(context) : _buildAddToQueueButton(),
          ),
          Audio audio => _getAudioTile(audio, audio.id == queue.currentId),
          Playlist playlist => ListTile(
            // Tapping plays it: all its audios are added to the queue and the first one starts.
            onTap: widget.isBeingAddedToQueue ? null : _onTap,
            leading: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 5,
              children: [
                if (widget.onAvatarPlay != null) IconButton(tooltip: 'Play', icon: const Icon(Icons.play_arrow), onPressed: widget.onAvatarPlay),
                AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/playlist/avatar/${playlist.id}', placeholderIcon: Icons.queue_music),
              ],
            ),
            title: _buildSingleLineText(playlist.name),
            trailing: _buildAddToQueueButton(),
          ),
          WithId() => throw UnimplementedError(),
        };
      },
    );
  }

  // ── Reacting to taps ───────────────────────────────────────────────────────

  /// The tap handler of a row, or null when tapping it does nothing.
  Future<void> _onTap() async {
    widget.onTap?.call();

    _onResultTapped(widget.item);
  }

  OverlayEntry? _albumAudiosEntry;
  void _onResultTapped(WithId item) async {
    if (item is Artist) {
      context.push(Uri(path: kArtistDetailsRoutePath, queryParameters: {'artistId': item.id}).toString());
    } else if (item is Audio) {
      AudioPlayerService.add(audioId: item.id);
    } else if (item is Playlist) {
      // All of the playlist's audios go into the queue and the first of them starts playing.
      unawaited(ref.read(musicSearchControllerProvider.notifier).addAlbumOrPlaylistToQueue(item, playImmediately: true));
    } else if (item is Album) {
      final List<Audio>? audios = await ref.read(musicSearchApiProvider).fetchAllAudiosOfAlbum(item.id);
      if (!mounted) return;

      if (audios == null) return;

      final musicSearchState = ref.watch(musicSearchControllerProvider);
      final overlay = rootNavigatorKey.currentState?.overlay;
      _albumAudiosEntry = OverlayEntry(
        builder: (context) {
          final theme = Theme.of(context);

          return Popup(
            constraints: const BoxConstraints(maxWidth: 1000),
            leadings: [
              const Icon(Icons.album),
              Text(item.name, style: theme.textTheme.titleMedium),
            ],
            onClose: () {
              _albumAudiosEntry?.remove();
            },
            child: ScrollableList(
              loadNextPage: ({retryAfterError = false}) {},
              onRefresh: () async {},
              itemCount: audios.length,
              loadMoreMode: LoadMoreMode.infiniteScroll,
              itemBuilder: (context, index) => SearchResultTile(
                item: audios[index],
                isEditModeEnabled: musicSearchState.isEditModeEnabled,
                isBeingDeleted: musicSearchState.idsBeingDeleted.contains(audios[index].id),
                isBeingAddedToQueue: musicSearchState.idsBeingAddedToQueue.contains(audios[index].id),
              ),
            ),
          );
        },
      );

      if (_albumAudiosEntry != null) overlay?.insert(_albumAudiosEntry!);
    }
  }

  // ── Editing ────────────────────────────────────────────────────────────────

  /// Opens the edit page of [item]; refreshes the affected tab(s) when the user comes back.
  Future<void> _onEdit(WithId item) async {
    if (item is Audio) {
      await _openEditPageOfAudio(item);
    } else if (item is Artist) {
      await _openEditPageOfArtist(item);
    } else if (item is Album) {
      await _openEditPageOfAlbum(item);
    }
  }

  OverlayEntry? _audioEntry;
  Future<void> _openEditPageOfAudio(Audio audio) async {
    final overlay = rootNavigatorKey.currentState?.overlay;
    _audioEntry = OverlayEntry(
      builder: (context) {
        return Popup(
          constraints: const BoxConstraints(maxWidth: 1000),
          leadings: [Text(audio.title)],
          onClose: () {
            _audioEntry?.remove();
          },
          child: EditAudioPage(audioId: audio.id),
        );
      },
    );

    if (_audioEntry != null) overlay?.insert(_audioEntry!);
  }

  OverlayEntry? _artistEntry;
  Future<void> _openEditPageOfArtist(Artist artist) async {
    final overlay = rootNavigatorKey.currentState?.overlay;
    _artistEntry = OverlayEntry(
      builder: (context) {
        return Popup(
          constraints: const BoxConstraints(maxWidth: 1000),
          leadings: [Text(artist.name)],
          onClose: () {
            _artistEntry?.remove();
          },
          child: EditArtistPage(artistId: artist.id),
        );
      },
    );

    if (_artistEntry != null) overlay?.insert(_artistEntry!);
  }

  OverlayEntry? _albumEntry;
  Future<void> _openEditPageOfAlbum(Album album) async {
    final overlay = rootNavigatorKey.currentState?.overlay;
    _albumEntry = OverlayEntry(
      builder: (context) {
        return Popup(
          constraints: const BoxConstraints(maxWidth: 1000),
          leadings: [Text(album.name)],
          onClose: () {
            _albumEntry?.remove();
          },
          child: EditAlbumPage(albumId: album.id),
        );
      },
    );

    if (_albumEntry != null) overlay?.insert(_albumEntry!);
  }

  Future<void> _onDelete() async {
    if (kShouldConfirmBeforeDelete) {
      final wasConfirmed = await showDeleteConfirmationDialog(context, item: widget.item);
      if (!wasConfirmed || !mounted) return;
    }

    final searchController = ref.read(musicSearchControllerProvider.notifier);
    if (widget.item is Audio) {
      await searchController.deleteAudio(widget.item.id);
    } else if (widget.item is Album) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);

          return AlertDialog(
            title: const Text('Delete all audios?'),
            content: Text(
              'Every audio of "${(widget.item as Album).name}" will be deleted, one by one. '
              'They disappear from every album, artist and playlist they are in. This cannot be undone.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete all'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;

      await searchController.deleteAllAudiosOfAlbum(widget.item as Album);

      await searchController.deleteArtistOrAlbum(widget.item);
    } else {
      await searchController.deleteArtistOrAlbum(widget.item);
    }
  }

  Widget _buildSingleLineText(String text) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

  Widget _buildEditModeActions(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: widget.isBeingDeleted ? null : (widget.onEdit ?? () => _onEdit(widget.item)),
        ),
        if (widget.isBeingDeleted)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: widget.onDelete == null ? null : _onDelete,
          ),
      ],
    );
  }

  /// "Add to queue" (spinner while the audios are being fetched).
  Widget? _buildAddToQueueButton() {
    if (widget.onAddToQueue == null) return null;
    if (widget.isBeingAddedToQueue) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return IconButton(tooltip: 'Add to queue', icon: const Icon(Icons.playlist_add), onPressed: widget.onAddToQueue);
  }

  /// Duration (when there is room) and the "add to queue" / "add to playlist" buttons.
  Widget _buildAudioTrailing(BuildContext context, Audio audio) {
    final durationInSeconds = audio.technical?.durationSec;
    final hasRoomForDuration = MediaQuery.sizeOf(context).width >= _minimumScreenWidthToShowAudioDuration;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (durationInSeconds != null && hasRoomForDuration) Text(_formatAsMinutesAndSeconds(durationInSeconds.round())),
        AudioRowActions(audioId: audio.id, initialPlaylistName: audio.title),
      ],
    );
  }

  static String _formatAsMinutesAndSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final remainingSeconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }
}
