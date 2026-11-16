import 'package:avarim/api/models/audio.dart';
import 'package:avarim/app_config.dart';
import 'package:avarim/components/contents/audio_row_actions.dart';
import 'package:avarim/components/core/core.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/music_search_api.dart';
import '../artists_subtitles.dart';
import '../authenticated_thumbnail.dart';
import '../popups/entity_popups.dart';
import 'item_actions.dart';

/// A list row for an [Audio]: tap plays it; in edit mode it has edit / delete buttons instead of the
/// duration and the queue / playlist buttons. Highlighted while it is the current track.
class AudioListItem extends ConsumerStatefulWidget {
  const AudioListItem({super.key, required this.audio, this.onTap, this.isEditMode = false, this.onDeleted});

  /// Narrower screens only have room for the audio's buttons, not for its duration.
  static const _minimumScreenWidthToShowDuration = 480;

  final Audio audio;

  /// Called on tap, before the audio starts playing.
  final VoidCallback? onTap;

  /// Shows edit / delete buttons.
  final bool isEditMode;

  /// Called with the audio's id once it was deleted (so the list can drop it).
  final ValueChanged<String>? onDeleted;

  @override
  ConsumerState<AudioListItem> createState() => _AudioListItemState();
}

class _AudioListItemState extends ConsumerState<AudioListItem> {
  bool _isDeleting = false;

  void _play() {
    widget.onTap?.call();
    AudioPlayerService.add(audioId: widget.audio.id);
  }

  Future<void> _delete() async {
    if (!mounted) return;

    setState(() => _isDeleting = true);
    await onDeleteAudio(context, ref, widget.audio, onDeleted: widget.onDeleted);
    if (mounted) setState(() => _isDeleting = false);
  }

  @override
  Widget build(BuildContext context) {
    final audio = widget.audio;

    return ValueListenableBuilder<AudioQueueState>(
      valueListenable: AudioPlayerService.queue,
      builder: (context, queue, _) => ListTile(
        onTap: _isDeleting ? null : _play,
        selected: audio.id == queue.currentId,
        leading: AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/audio/coverArt/${audio.id}', placeholderIcon: Icons.music_note),
        title: SingleLineText(audio.title),
        // an audio's artists are resolved from its links (they aren't part of the audio document)
        subtitle: AudioArtistsSubtitle(audioId: audio.id),
        trailing: widget.isEditMode
            ? EditDeleteActions(isBusy: _isDeleting, onEdit: () => showEditPopup(audio), onDelete: _delete)
            : _buildDurationAndActions(context),
      ),
    );
  }

  Widget _buildDurationAndActions(BuildContext context) {
    final durationInSeconds = widget.audio.technical?.durationSec;
    final hasRoomForDuration = MediaQuery.sizeOf(context).width >= AudioListItem._minimumScreenWidthToShowDuration;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (durationInSeconds != null && hasRoomForDuration) Text(_formatAsMinutesAndSeconds(durationInSeconds.round())),
        AudioRowActions(audioId: widget.audio.id, initialPlaylistName: widget.audio.title),
      ],
    );
  }

  static String _formatAsMinutesAndSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final remainingSeconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }
}
