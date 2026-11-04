import 'package:avarim/api/providers/audio_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The artists of an audio, e.g. "Artist A, Artist B". They are looked up per audio (and cached), see
/// audioArtistsProvider. A blank line is shown meanwhile so the row keeps its height.
class AudioArtistsSubtitle extends ConsumerWidget {
  const AudioArtistsSubtitle({super.key, required this.audioId});

  final String audioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistsLabelText = artistsLabel(ref.watch(audioArtistsProvider(audioId)).value);
    return Text(artistsLabelText ?? ' ', maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

/// The artists of an album, e.g. "Artist A, Artist B". Album names repeat, so this tells them apart.
class AlbumArtistsSubtitle extends ConsumerWidget {
  const AlbumArtistsSubtitle({super.key, required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistsLabelText = artistsLabel(ref.watch(albumArtistsProvider(albumId)).value);
    return Text(artistsLabelText ?? ' ', maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}
