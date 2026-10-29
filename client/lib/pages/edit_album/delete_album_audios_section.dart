// delete_album_audios_section.dart
//
// "Danger zone" of the edit album page: deletes EVERY audio of the album, one request at a time
// (DELETE /api/audio/:audioId, admin only), after a confirmation dialog. The audios are removed everywhere (an
// audio that is also in another album, an artist's singles or a playlist disappears from those too), not just
// from this album.
//
//   ids        GET /api/relationship/album/audio?albumId&page&pageSize   (all pages, loaded before anything is deleted)
//   delete     DELETE /api/audio/:audioId                   (one by one, stops at the first failure)
//
// Progress is shown inline with a Cancel button (the audio being deleted finishes first).

import 'dart:async';

import 'package:avarim/api/controllers/audio_controller.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/pages/search/search_page.dart' show musicSearchApiProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeleteAlbumAudiosSection extends ConsumerStatefulWidget {
  const DeleteAlbumAudiosSection({super.key, required this.albumId, required this.albumName});

  final String albumId;
  final String albumName;

  @override
  ConsumerState<DeleteAlbumAudiosSection> createState() => _DeleteAlbumAudiosSectionState();
}

class _DeleteAlbumAudiosSectionState extends ConsumerState<DeleteAlbumAudiosSection> {
  bool _loading = false; // fetching the ids
  bool _running = false; // deleting
  bool _cancelled = false;
  int _done = 0;
  int _total = 0;

  Future<void> _start() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all audios?'),
        content: Text(
          'Every audio of "${widget.albumName}" will be deleted, one by one. '
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
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _cancelled = false;
      _done = 0;
      _total = 0;
    });

    final ids = await ref.read(musicSearchApiProvider).albumAudioIds(widget.albumId);
    if (!mounted) return;

    if (ids == null) {
      setState(() => _loading = false); // the error was already shown
      return;
    }
    if (ids.isEmpty) {
      setState(() => _loading = false);
      NotificationService.showError(message: 'This album has no audios');
      return;
    }

    setState(() {
      _loading = false;
      _running = true;
      _total = ids.length;
    });

    final controller = ref.read(audioControllerProvider);
    var failed = false;
    for (final id in ids) {
      if (_cancelled || !mounted) break;

      final deleted = await controller.delete(audioId: id);
      if (!mounted) return;

      if (!deleted) {
        failed = true; // the error was already shown
        break;
      }
      setState(() => _done++);
    }
    if (!mounted) return;

    final done = _done;
    final cancelled = _cancelled;
    setState(() => _running = false);

    final what = done == 1 ? '1 audio' : '$done audios';
    if (failed) {
      NotificationService.showError(message: 'Stopped: deleted $what of ${ids.length}');
    } else if (cancelled) {
      NotificationService.showSuccess(message: 'Cancelled: deleted $what of ${ids.length}');
    } else {
      NotificationService.showSuccess(message: 'Deleted $what');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _loading || _running;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Danger zone', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error)),
        const SizedBox(height: 8),
        Text('Deletes every audio of this album, one at a time. They are removed everywhere, not only from this album.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (_running) ...[
          LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Deleting $_done / $_total'),
              const Spacer(),
              TextButton(onPressed: _cancelled ? null : () => setState(() => _cancelled = true), child: Text(_cancelled ? 'Cancelling...' : 'Cancel')),
            ],
          ),
        ] else
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error, side: BorderSide(color: theme.colorScheme.error)),
            onPressed: busy ? null : _start,
            icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_sweep_outlined),
            label: const Text('Delete all audios of this album'),
          ),
      ],
    );
  }
}
