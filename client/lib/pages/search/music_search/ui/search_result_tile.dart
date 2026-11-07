import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/app_config.dart';
import 'package:avarim/components/contents/audio_row_actions.dart';
import 'package:flutter/material.dart';

import 'artists_subtitles.dart';
import 'authenticated_thumbnail.dart';

/// One row of the results: an artist, an album, an audio or a playlist.
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.item,
    this.onTap,
    this.isPlaying = false,
    this.isEditModeEnabled = false,
    this.isBeingDeleted = false,
    this.isBeingAddedToQueue = false,
    this.onEdit,
    this.onDelete,
    this.onAddToQueue,
    this.onAvatarPlay,
  });

  /// Narrower screens only have room for the audio's buttons, not for its duration.
  static const _minimumScreenWidthToShowAudioDuration = 480;

  final WithId item;
  final VoidCallback? onTap;

  /// True for the audio currently loaded in the floating player.
  final bool isPlaying;

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
  Widget build(BuildContext context) {
    return switch (item) {
      Artist artist => ListTile(
        onTap: onTap,
        leading: AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/artist/avatar/${artist.id}', placeholderIcon: Icons.person, isCircular: true),
        title: _buildSingleLineText(artist.name),
        trailing: isEditModeEnabled ? _buildEditModeActions(context) : null,
      ),
      Album album => ListTile(
        onTap: onTap,
        leading: FittedBox(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 5,
            children: [
              if (onAvatarPlay != null) IconButton(tooltip: 'Play', icon: const Icon(Icons.play_arrow), onPressed: onAvatarPlay),
              AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/album/avatar/${album.id}', placeholderIcon: Icons.album),
            ],
          ),
        ),
        title: _buildSingleLineText(album.name),
        subtitle: AlbumArtistsSubtitle(albumId: album.id),
        trailing: isEditModeEnabled ? _buildEditModeActions(context) : _buildAddToQueueButton(),
      ),
      Audio audio => ListTile(
        onTap: isBeingDeleted ? null : onTap,
        selected: isPlaying,
        leading: AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/audio/coverArt/${audio.id}', placeholderIcon: Icons.music_note),
        title: _buildSingleLineText(audio.title),
        // an audio's artists are resolved from its links (they aren't part of the audio document)
        subtitle: AudioArtistsSubtitle(audioId: audio.id),
        trailing: isEditModeEnabled ? _buildEditModeActions(context) : _buildAudioTrailing(context, audio),
      ),
      Playlist playlist => ListTile(
        // Tapping plays it: all its audios are added to the queue and the first one starts.
        onTap: isBeingAddedToQueue ? null : onTap,
        leading: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 5,
          children: [
            if (onAvatarPlay != null) IconButton(tooltip: 'Play', icon: const Icon(Icons.play_arrow), onPressed: onAvatarPlay),
            AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/playlist/avatar/${playlist.id}', placeholderIcon: Icons.queue_music),
          ],
        ),
        title: _buildSingleLineText(playlist.name),
        trailing: _buildAddToQueueButton(),
      ),
      WithId() => throw UnimplementedError(),
    };
  }

  Widget _buildSingleLineText(String text) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

  Widget _buildEditModeActions(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onEdit != null) IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: isBeingDeleted ? null : onEdit),
        if (isBeingDeleted)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (onDelete != null)
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: onDelete,
          ),
      ],
    );
  }

  /// "Add to queue" (spinner while the audios are being fetched).
  Widget? _buildAddToQueueButton() {
    if (onAddToQueue == null) return null;
    if (isBeingAddedToQueue) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return IconButton(tooltip: 'Add to queue', icon: const Icon(Icons.playlist_add), onPressed: onAddToQueue);
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
