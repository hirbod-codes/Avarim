import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/app_config.dart';
import 'package:avarim/components/core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/music_search_api.dart';
import '../authenticated_thumbnail.dart';
import 'add_to_queue_button.dart';
import 'item_actions.dart';

/// A list row for a [Playlist]: tap appends all its audios to the player queue and starts the first of them,
/// the play button replaces the queue with them, the trailing button only appends them.
class PlaylistListItem extends ConsumerStatefulWidget {
  const PlaylistListItem({super.key, required this.playlist, this.onTap});

  final Playlist playlist;

  /// Called on tap, before the playlist's audios are queued.
  final VoidCallback? onTap;

  @override
  ConsumerState<PlaylistListItem> createState() => _PlaylistListItemState();
}

class _PlaylistListItemState extends ConsumerState<PlaylistListItem> {
  bool _isAddingToQueue = false;

  Future<void> _queueAudios({required bool replaceQueue, required bool playImmediately}) async {
    if (_isAddingToQueue) return;
    setState(() => _isAddingToQueue = true);

    final api = ref.read(musicSearchApiProvider);
    await queueAudios(fetchAudios: () => api.fetchAllAudiosOfPlaylist(widget.playlist.id), replaceQueue: replaceQueue, playImmediately: playImmediately);

    if (mounted) setState(() => _isAddingToQueue = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: _isAddingToQueue
          ? null
          : () {
              widget.onTap?.call();
              _queueAudios(replaceQueue: false, playImmediately: true);
            },
      leading: LeadingWithAction(
        onAction: () => _queueAudios(replaceQueue: true, playImmediately: true),
        child: AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/playlist/avatar/${widget.playlist.id}', placeholderIcon: Icons.queue_music),
      ),
      title: SingleLineText(widget.playlist.name),
      trailing: AddToQueueButton(isBusy: _isAddingToQueue, onPressed: () => _queueAudios(replaceQueue: false, playImmediately: false)),
    );
  }
}
