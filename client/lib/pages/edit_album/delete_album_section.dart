import 'dart:async';

import 'package:avarim/api/models/album.dart';
import 'package:avarim/pages/search/music_search/controller/music_search_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeleteAlbumSection extends ConsumerStatefulWidget {
  const DeleteAlbumSection({super.key, required this.album});

  final Album album;

  @override
  ConsumerState<DeleteAlbumSection> createState() => _DeleteAlbumSectionState();
}

class _DeleteAlbumSectionState extends ConsumerState<DeleteAlbumSection> {
  bool _running = false; // deleting

  Future<void> _start() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all audios?'),
        content: Text(
          'The album: "${widget.album.name}" will be deleted.'
          'Are you sure?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete the album'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;

    setState(() {
      _running = true;
    });

    await ref.read(musicSearchControllerProvider.notifier).deleteArtistOrAlbum(widget.album);
    if (!mounted) return;

    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _running;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Danger zone', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error)),
        const SizedBox(height: 8),
        Text('Deletes this album.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error),
          ),
          onPressed: busy ? null : _start,
          icon: _running ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_sweep_outlined),
          label: const Text('Delete this album'),
        ),
      ],
    );
  }
}
