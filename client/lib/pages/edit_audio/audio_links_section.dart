// audio_links_section.dart
//
// "Artists & albums" of EditAudioPage. An audio isn't stored with its artists / albums: it has relationships
// (artist-album-audio rows). Each row is a PAIR with both sides optional:
//   artist + album    the audio is on that album, credited to that artist
//   artist only       one of the artist's singles
//   album only        on the album, with no artist
// Pairs are added / removed right away (admin only). The artist / album must already exist, so the fields
// suggest existing ones and offer to create a new one first.
//
//   pairs   GET    /api/relationship/audio/...                       (audioLinksProvider)
//   add     POST   /api/relationship { audioId, artistId?, albumId? }
//   remove  DELETE /api/relationship { audioId, artistId, albumId }
//   create  POST   /api/artist?name        POST /api/album?name

import 'package:avarim/api/controllers/library_controller.dart';
import 'package:avarim/api/controllers/relationship_controller.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio_link.dart';
import 'package:avarim/api/providers/audio_links.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/pages/common/link_autocomplete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AudioLinksSection extends ConsumerStatefulWidget {
  const AudioLinksSection({super.key, required this.audioId});

  final String audioId;

  @override
  ConsumerState<AudioLinksSection> createState() => _AudioLinksSectionState();
}

class _AudioLinksSectionState extends ConsumerState<AudioLinksSection> {
  bool _busy = false;

  // The pair being put together (not saved until "Add").
  Artist? _artist;
  Album? _album;

  String get _id => widget.audioId;

  void _refresh() {
    ref.invalidate(audioLinksProvider(_id));
    ref.invalidate(audioArtistsProvider(_id));
    ref.invalidate(audioAlbumsProvider(_id));
  }

  /// Runs one change. The lists are reloaded afterwards, also when it failed half-way.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  // ---- creating the artist / album ----------------------------------------

  Future<void> _createArtist(String name) async {
    if (_busy) return;
    final ok = await _confirm(context, title: 'Create artist', body: 'Create the artist "$name"?', action: 'Create');
    if (!ok || !mounted) return;

    await _run(() async {
      final artist = await ref.read(libraryControllerProvider).createArtist(name); // a toast says why it failed
      if (artist != null && mounted) setState(() => _artist = artist);
    });
  }

  Future<void> _createAlbum(String name) async {
    if (_busy) return;
    final chosen = await showDialog<String>(context: context, builder: (_) => _AlbumNameDialog(initialName: name));
    if (chosen == null || !mounted) return;

    await _run(() async {
      final album = await ref.read(libraryControllerProvider).createAlbum(name: chosen); // a toast says why it failed
      if (album != null && mounted) setState(() => _album = album);
    });
  }

  // ---- add / remove a pair -------------------------------------------------

  Future<void> _add(List<AudioLink> current) async {
    if (_busy) return;
    final link = AudioLink(artist: _artist, album: _album);
    if (link.artist == null && link.album == null) return;

    if (current.contains(link)) {
      NotificationService.showError(message: 'This audio already has it');
      return;
    }

    await _run(() async {
      final ok = await ref.read(relationshipControllerProvider).create(audioId: _id, artistId: link.artist?.id, albumId: link.album?.id);
      if (ok && mounted) {
        setState(() {
          _artist = null;
          _album = null;
        });
      }
    });
  }

  Future<void> _remove(AudioLink link, List<AudioLink> current) async {
    if (_busy) return;
    final ok = await _confirm(context, title: 'Remove', body: 'Remove ${_describe(link)} from this audio?', action: 'Remove');
    if (!ok || !mounted) return;

    await _run(() async {
      await ref.read(relationshipControllerProvider).removeLink(audioId: _id, link: link, current: current);
    });
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ref.read(libraryControllerProvider);
    final links = ref.watch(audioLinksProvider(_id));
    final list = links.value ?? const <AudioLink>[];
    final loading = _busy || links.isLoading;
    final canAdd = !_busy && (_artist != null || _album != null);

    final artistField = LinkAutocomplete<Artist>(
      label: 'Artist (optional)',
      hint: 'Type a name to search',
      enabled: !_busy,
      search: library.searchArtists,
      labelOf: (a) => a.name,
      onPick: (a) async => setState(() => _artist = a),
      onCreate: _createArtist,
      createLabel: 'Create artist',
    );
    final albumField = LinkAutocomplete<Album>(
      label: 'Album (optional)',
      hint: 'Type a name to search',
      enabled: !_busy,
      search: library.searchAlbums,
      labelOf: (a) => a.name,
      onPick: (a) async => setState(() => _album = a),
      onCreate: _createAlbum,
      createLabel: 'Create album',
      // album names repeat, so creating one is always offered; the artists tell same-named albums apart
      alwaysOfferCreate: true,
      optionSubtitle: (a) => _AlbumArtists(a.id),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Artists & albums', style: theme.textTheme.titleLarge),
            if (loading) ...[const SizedBox(width: 12), const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))],
          ],
        ),
        const SizedBox(height: 4),
        Text('Each row is an artist and / or an album. Changes are saved right away.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),

        if (links.hasError)
          _LoadError(onRetry: _refresh)
        else if (list.isEmpty)
          Text(links.isLoading ? 'Loading...' : 'No artists or albums', style: theme.textTheme.bodyMedium)
        else
          for (final link in list) _PairTile(key: ValueKey('pair-${link.key}'), link: link, onRemove: () => _remove(link, list)),

        const SizedBox(height: 16),
        Text('Add', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= 560) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: artistField),
                  const SizedBox(width: 12),
                  Expanded(child: albumField),
                ],
              );
            }
            return Column(children: [artistField, const SizedBox(height: 12), albumField]);
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: (_artist == null && _album == null)
                  ? Text('Pick an artist and / or an album, then press Add.', style: theme.textTheme.bodySmall)
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (_artist != null) InputChip(avatar: const Icon(Icons.person, size: 18), label: Text(_artist!.name), onDeleted: () => setState(() => _artist = null)),
                        if (_album != null) InputChip(avatar: const Icon(Icons.album, size: 18), label: Text(_album!.name), onDeleted: () => setState(() => _album = null)),
                      ],
                    ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(onPressed: canAdd ? () => _add(list) : null, icon: const Icon(Icons.add), label: const Text('Add')),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small widgets
// ---------------------------------------------------------------------------

/// "Artist" and "Album" of a pair as text, e.g. `"Artist" on "Album"`.
String _describe(AudioLink link) {
  final artist = link.artist;
  final album = link.album;
  if (artist != null && album != null) return '"${artist.name}" on "${album.name}"';
  if (artist != null) return '"${artist.name}" (no album)';
  if (album != null) return '"${album.name}" (no artist)';
  return 'this';
}

/// The artists of an album ("No artist" when it has none), shown under a suggestion.
class _AlbumArtists extends ConsumerWidget {
  const _AlbumArtists(this.albumId);

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(albumArtistsProvider(albumId));
    return Text(artists.hasError ? '' : (artistsLabel(artists.value) ?? (artists.isLoading ? '...' : 'No artist')), maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

/// One pair: the artist, the album, and a remove button.
class _PairTile extends StatelessWidget {
  const _PairTile({super.key, required this.link, required this.onRemove});

  final AudioLink link;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.onSurfaceVariant);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(link.album != null ? Icons.album_outlined : Icons.person_outline),
      title: Text(link.artist?.name ?? 'No artist', style: link.artist == null ? muted : null),
      subtitle: Text(link.album?.name ?? 'No album', style: link.album == null ? muted : null),
      trailing: IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline), onPressed: onRemove),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text("Couldn't load", style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(width: 8),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

Future<bool> _confirm(BuildContext context, {required String title, required String body, required String action}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for the name of the album to create. Pops with the trimmed name.
class _AlbumNameDialog extends StatefulWidget {
  const _AlbumNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_AlbumNameDialog> createState() => _AlbumNameDialogState();
}

class _AlbumNameDialogState extends State<_AlbumNameDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    return AlertDialog(
      title: const Text('Create album'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Album name', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => name.isEmpty ? null : Navigator.pop(context, name),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: name.isEmpty ? null : () => Navigator.pop(context, name), child: const Text('Create')),
      ],
    );
  }
}
