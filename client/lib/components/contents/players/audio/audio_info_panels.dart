// audio_info_panels.dart  (next to audio_player_screen.dart)
//
// Three toggle buttons + the panel they open inside the player:
//   - lyrics     -> lyricists ("Lyrics by ...") and the lyrics text
//   - tags       -> every tag EXCEPT lyrics and lyricists
//   - technical  -> codec, bitrate, sample rate, hashes, dates ...
//
// A button only appears when the audio has something to show for it, and
// nothing is rendered when it has none.

import 'package:avarim/api/models/audio.dart';
import 'package:flutter/material.dart';

enum AudioInfoPanel { lyrics, tags, technical }

// ─────────────────────────────────────────────────────────────────────────────
// What each panel contains
// ─────────────────────────────────────────────────────────────────────────────

typedef _Rows = List<MapEntry<String, String>>;

class _RowBuilder {
  final _Rows rows = [];

  void add(String label, String? value) {
    final v = value?.trim();
    if (v != null && v.isNotEmpty) rows.add(MapEntry(label, v));
  }

  void addList(String label, List<String> values) => add(label, values.where((v) => v.trim().isNotEmpty).join(', '));
}

String? _pair(int? a, int? b) => a == null ? null : (b == null ? '$a' : '$a / $b');

/// Everything in [AudioTags] except `lyrics` and `lyricists`.
_Rows _tagRows(AudioTags t) {
  final b = _RowBuilder();
  b.add('File title', t.audioTitle);
  b.addList('Artists', t.artists);
  b.addList('Album artists', t.albumArtists);
  b.add('Album', t.album);
  b.add('Track', _pair(t.trackNumber, t.trackTotal));
  b.add('Disc', _pair(t.discNumber, t.discTotal));
  b.add('Year', t.year?.toString());
  b.add('Release date', t.releaseDate);
  b.addList('Genres', t.genres);
  b.addList('Composers', t.composers);
  b.addList('Producers', t.producers);
  b.add('Label', t.label);
  b.add('Catalog no.', t.catalogNumber);
  b.addList('ISRC', t.isrc);
  final bpm = t.bpm;
  b.add('BPM', bpm == null ? null : (bpm == bpm.roundToDouble() ? '${bpm.round()}' : bpm.toStringAsFixed(1)));
  b.add('Key', t.key);
  if (t.compilation) b.add('Compilation', 'Yes');
  b.add('Language', t.language);
  b.add('Copyright', t.copyright);
  b.add('Comment', t.comment);
  return b.rows;
}

String _bytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return i == 0 ? '$bytes B' : '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[i]}';
}

String _duration(double sec) {
  final s = sec.round();
  final h = s ~/ 3600;
  final m = ((s % 3600) ~/ 60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$ss' : '$m:$ss';
}

// ffprobe reports bits per second; values below 1000 are assumed to already be kbps.
String _bitrate(double v) => v >= 1000 ? '${(v / 1000).round()} kbps' : '${v.round()} kbps';

String _sampleRate(double hz) => hz % 1000 == 0 ? '${(hz / 1000).round()} kHz' : '${(hz / 1000).toStringAsFixed(1)} kHz';

String _date(DateTime d) => d.toLocal().toString().split('.').first;

_Rows _technicalRows(Audio a) {
  final b = _RowBuilder();
  final t = a.technical;

  if (t != null) {
    b.add('Container', t.container);
    b.add('Format', t.ffprobeFormat);
    b.add('Codec', [t.codec, t.codecProfile].whereType<String>().where((s) => s.isNotEmpty).join(' · '));
    if (t.lossless != null) b.add('Lossless', t.lossless! ? 'Yes' : 'No');
    if (t.durationSec != null) b.add('Duration', _duration(t.durationSec!));
    if (t.bitrate != null) b.add('Bitrate', _bitrate(t.bitrate!));
    if (t.sampleRate != null) b.add('Sample rate', _sampleRate(t.sampleRate!));
    if (t.bitDepth != null) b.add('Bit depth', '${t.bitDepth}-bit');
    b.add('Channels', [if (t.channels != null) '${t.channels}', t.channelLayout].whereType<String>().where((s) => s.isNotEmpty).join(' · '));
    b.add('Encoder', t.encoder);
    if (t.sizeBytes != null) b.add('File size', _bytes(t.sizeBytes!));
    if (a.totalFilesBytes != null && a.totalFilesBytes != t.sizeBytes) b.add('Stored size', _bytes(a.totalFilesBytes!));
    b.addList('Tag types', t.tagTypes);
    b.add('SHA-256', t.sha256);
    b.add('Audio SHA-256', t.audioSha256);
  }
  if (a.createdAt != null) b.add('Added', _date(a.createdAt!));
  if (a.updatedAt != null) b.add('Updated', _date(a.updatedAt!));

  return b.rows;
}

bool _hasLyricsPanel(Audio a) => (a.tags?.lyrics?.trim().isNotEmpty ?? false) || (a.tags?.lyricists.any((l) => l.trim().isNotEmpty) ?? false);
bool _hasTagsPanel(Audio a) => a.tags != null && _tagRows(a.tags!).isNotEmpty;
bool _hasTechnicalPanel(Audio a) => _technicalRows(a).isNotEmpty;

bool _has(Audio a, AudioInfoPanel p) => switch (p) {
  AudioInfoPanel.lyrics => _hasLyricsPanel(a),
  AudioInfoPanel.tags => _hasTagsPanel(a),
  AudioInfoPanel.technical => _hasTechnicalPanel(a),
};

// ─────────────────────────────────────────────────────────────────────────────
// Buttons
// ─────────────────────────────────────────────────────────────────────────────

/// Compact icon buttons (lyrics / tags / technical). Tapping the selected one again closes the panel.
class AudioInfoButtons extends StatelessWidget {
  const AudioInfoButtons({super.key, required this.audio, required this.selected, required this.onSelected});

  final Audio audio;
  final AudioInfoPanel? selected;
  final ValueChanged<AudioInfoPanel?> onSelected;

  static const _icons = {
    AudioInfoPanel.lyrics: (Icons.lyrics_outlined, Icons.lyrics, 'Lyrics'),
    AudioInfoPanel.tags: (Icons.sell_outlined, Icons.sell, 'Tags'),
    AudioInfoPanel.technical: (Icons.info_outline, Icons.info, 'Technical information'),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final panel in AudioInfoPanel.values)
          if (_has(audio, panel))
            IconButton(
              tooltip: _icons[panel]!.$3,
              isSelected: selected == panel,
              icon: Icon(_icons[panel]!.$1),
              selectedIcon: Icon(_icons[panel]!.$2),
              style: IconButton.styleFrom(
                foregroundColor: selected == panel ? scheme.onPrimaryContainer : null,
                backgroundColor: selected == panel ? scheme.primaryContainer : null,
              ),
              onPressed: () => onSelected(selected == panel ? null : panel),
            ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel
// ─────────────────────────────────────────────────────────────────────────────

/// Scrollable panel that fills the area it's given. Give it a `ValueKey(panel)`
/// so switching panels starts at the top.
class AudioInfoPanelView extends StatefulWidget {
  const AudioInfoPanelView({super.key, required this.audio, required this.panel, required this.onClose});

  final Audio audio;
  final AudioInfoPanel panel;
  final VoidCallback onClose;

  @override
  State<AudioInfoPanelView> createState() => _AudioInfoPanelViewState();
}

class _AudioInfoPanelViewState extends State<AudioInfoPanelView> {
  // Own controller: the panel lives in the root overlay where there is no PrimaryScrollController.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String get _title => switch (widget.panel) {
    AudioInfoPanel.lyrics => 'Lyrics',
    AudioInfoPanel.tags => 'Tags',
    AudioInfoPanel.technical => 'Technical information',
  };

  List<Widget> _content(BuildContext context) {
    final theme = Theme.of(context);

    switch (widget.panel) {
      case AudioInfoPanel.lyrics:
        final tags = widget.audio.tags;
        final lyricists = (tags?.lyricists ?? const <String>[]).where((l) => l.trim().isNotEmpty).toList();
        final lyrics = tags?.lyrics?.trim() ?? '';
        return [
          if (lyricists.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Lyrics by ${lyricists.join(', ')}', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
            ),
          if (lyrics.isNotEmpty)
            SelectableText(lyrics, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5))
          else
            Text('No lyrics available', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ];
      case AudioInfoPanel.tags:
        return [for (final e in _tagRows(widget.audio.tags ?? const AudioTags())) _InfoRow(label: e.key, value: e.value)];
      case AudioInfoPanel.technical:
        return [for (final e in _technicalRows(widget.audio)) _InfoRow(label: e.key, value: e.value)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Row(
              children: [
                Expanded(child: Text(_title, style: theme.textTheme.titleMedium)),
                IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: widget.onClose),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              child: ListView(controller: _scroll, primary: false, padding: const EdgeInsets.all(16), children: _content(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
