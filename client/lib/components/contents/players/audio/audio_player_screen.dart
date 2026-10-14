import 'dart:async';

import 'package:avarim/api/models/audio.dart';
import 'package:avarim/app_config.dart';
import 'package:avarim/components/contents/players/audio/audio_info_panels.dart';
import 'package:avarim/components/contents/players/audio/audio_player_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';

/// The background / gradient spans the full width, but the player's controls stay
/// centered at this width on wide screens instead of stretching edge to edge.
const kAudioPlayerContentMaxWidth = 560.0;

/// How faithful the gradient is to the cover art. `content` keeps the cover's own
/// saturation; `tonalSpot` (Material You default) is softer / more muted, `vibrant`
/// is punchier. Any [DynamicSchemeVariant] works.
const kCoverGradientVariant = DynamicSchemeVariant.content;

class AudioPlayerScreen extends ConsumerStatefulWidget {
  const AudioPlayerScreen({
    super.key,
    required this.audioId,
    required this.url,
    this.accessToken,
    this.headers,
    this.title,
    this.artist,
    this.albumArtUrl,
    this.audio,
    this.autoPlay = false,
    this.onCompleted,
  });

  final String audioId;
  final String url;
  final String? accessToken;
  final Map<String, String>? headers;
  final String? title;
  final String? artist;
  final String? albumArtUrl;

  /// The full audio document. Enables the lyrics / tags / technical buttons (hidden when null).
  final Audio? audio;

  /// Start playing as soon as the track has loaded.
  final bool autoPlay;

  /// Called once each time the track plays to its end.
  final VoidCallback? onCompleted;

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen> {
  StreamSubscription<AudioPlayerState>? _completionSub;
  AudioInfoPanel? _panel;

  /// Gradient stops (top -> bottom) derived from the cover art; null until loaded
  /// or when the audio has no cover art.
  List<Color>? _gradient;
  Brightness? _gradientBrightness;

  @override
  void initState() {
    super.initState();

    final commands = ref.read(audioPlayerCommandsProvider.notifier);

    // Fires onCompleted once per transition into `ended` (position ticks that
    // keep the status at `ended` don't re-fire it).
    var wasEnded = false;
    _completionSub = commands.stateStream.listen((s) {
      final ended = s.status == AudioPlayerStatus.ended;
      if (ended && !wasEnded && mounted) widget.onCompleted?.call();
      wasEnded = ended;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await commands.open(widget.url, headers: widget.headers, title: widget.title, artist: widget.artist, albumArtUrl: widget.albumArtUrl);

      if (!mounted || !widget.autoPlay || commands.currentState.hasError) return;
      // Not awaited: just_audio's play() only completes when playback stops.
      unawaited(commands.play());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadGradient(Theme.of(context).brightness);
  }

  @override
  void dispose() {
    _completionSub?.cancel();
    super.dispose();
  }

  /// Builds the gradient from the cover art's dominant colour. The colours come from a
  /// Material colour scheme generated in the CURRENT theme brightness, so they are
  /// deep / darkened in dark mode and soft / lightened in light mode, and are redone
  /// when the theme switches.
  Future<void> _loadGradient(Brightness brightness) async {
    final token = widget.accessToken;
    if (token == null || _gradientBrightness == brightness) return;
    _gradientBrightness = brightness;

    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: NetworkImage('${AppConfig.apiUrl}/api/audio/coverArt/${widget.audioId}', headers: {'Authorization': 'Bearer $token'}),
        brightness: brightness,
        dynamicSchemeVariant: kCoverGradientVariant,
      );
      if (!mounted || _gradientBrightness != brightness) return;
      setState(() => _gradient = [scheme.primaryContainer, scheme.tertiaryContainer, scheme.surface]);
    } catch (_) {
      // No cover art (or it failed to load): keep the plain background.
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(audioPlayerCommandsProvider.notifier);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      width: double.infinity,
      height: double.infinity,
      decoration: _gradient == null
          ? const BoxDecoration()
          : BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: _gradient!, stops: const [0.0, 0.55, 1.0]),
            ),
      child: StreamBuilder<AudioPlayerState>(
        stream: notifier.stateStream,
        initialData: notifier.currentState,
        builder: (context, snapshot) {
          final state = snapshot.data ?? const AudioPlayerState();
          if (state.hasError) {
            return _ErrorView(message: state.error ?? 'Unknown error');
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kAudioPlayerContentMaxWidth),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Album art + track info. An open info panel takes over exactly this area
                      // (the original stays laid out underneath so nothing jumps).
                      SizedBox(
                        width: double.infinity,
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            Visibility(
                              visible: _panel == null || widget.audio == null,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: Column(
                                children: [
                                  const SizedBox(height: 24),
                                  Container(
                                    constraints: BoxConstraints(maxHeight: 300),
                                    child: _AlbumArt(audioId: widget.audioId, accessToken: widget.accessToken),
                                  ),
                                  const SizedBox(height: 40),
                                  _TrackInfo(title: state.title, artist: state.artist),
                                  const SizedBox(height: 32),
                                ],
                              ),
                            ),
                            if (_panel != null && widget.audio != null)
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: AudioInfoPanelView(
                                    key: ValueKey(_panel),
                                    audio: widget.audio!,
                                    panel: _panel!,
                                    onClose: () => setState(() => _panel = null),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Row(
                            children: [
                              if (widget.audio != null) AudioInfoButtons(audio: widget.audio!, selected: _panel, onSelected: (p) => setState(() => _panel = p)),
                              const Spacer(),
                              _SpeedControls(state: state),
                            ],
                          ),
                          _SeekBar(state: state),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _MainControls(state: state),
                      const SizedBox(height: 24),
                      _VolumeControls(state: state),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Album art
// ---------------------------------------------------------------------------

class _AlbumArt extends StatelessWidget {
  const _AlbumArt({this.audioId, this.accessToken});
  final String? audioId;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 32, offset: const Offset(0, 16))],
        ),
        clipBehavior: Clip.antiAlias,
        child: audioId != null && accessToken != null
            ? Image.network('${AppConfig.apiUrl}/api/audio/coverArt/$audioId', fit: BoxFit.cover, headers: {'Authorization': 'Bearer $accessToken'})
            : Icon(Icons.music_note_rounded, size: 80, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Track info
// ---------------------------------------------------------------------------

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({this.title, this.artist});
  final String? title;
  final String? artist;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title ?? 'Unknown Track',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          artist ?? 'Unknown Artist',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Seek bar
// ---------------------------------------------------------------------------

class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar({required this.state});
  final AudioPlayerState state;

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _draggingValue;

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _draggingValue ?? widget.state.progress;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            secondaryActiveTrackColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            secondaryTrackValue: widget.state.bufferedProgress,
            onChangeStart: (_) => setState(() => _draggingValue = progress),
            onChanged: (v) => setState(() => _draggingValue = v),
            onChangeEnd: (v) {
              setState(() => _draggingValue = null);
              final target = Duration(milliseconds: (v * widget.state.duration.inMilliseconds).round());
              ref.read(audioPlayerCommandsProvider.notifier).seek(target);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_format(widget.state.position), style: Theme.of(context).textTheme.labelMedium),
              Text(_format(widget.state.duration), style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Main controls
// ---------------------------------------------------------------------------

class _MainControls extends ConsumerWidget {
  const _MainControls({required this.state});
  final AudioPlayerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(audioPlayerCommandsProvider.notifier);
    final isLoading = state.isLoading || state.isBuffering;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(iconSize: 40, onPressed: () => commands.skipBackward(), icon: const Icon(Icons.replay_10_rounded)),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
          child: isLoading
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: CircularProgressIndicator(strokeWidth: 3, color: Theme.of(context).colorScheme.onPrimary),
                )
              : IconButton(
                  iconSize: 36,
                  color: Theme.of(context).colorScheme.onPrimary,
                  onPressed: () => commands.togglePlayPause(),
                  icon: Icon(
                    state.status == AudioPlayerStatus.ended
                        ? Icons.replay_rounded
                        : state.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
        ),
        IconButton(iconSize: 40, onPressed: () => commands.skipForward(), icon: const Icon(Icons.forward_10_rounded)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Volume controls: speed + volume
// ---------------------------------------------------------------------------

class _VolumeControls extends ConsumerWidget {
  const _VolumeControls({required this.state});
  final AudioPlayerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(audioPlayerCommandsProvider.notifier);

    return Row(
      children: [
        const Icon(Icons.volume_down_rounded, size: 20),
        Expanded(
          child: Slider(value: state.volume.clamp(0.0, 1.0), onChanged: (v) => commands.setVolume(v)),
        ),
        const Icon(Icons.volume_up_rounded, size: 20),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Speed controls: speed + volume
// ---------------------------------------------------------------------------

class _SpeedControls extends ConsumerWidget {
  const _SpeedControls({required this.state});
  final AudioPlayerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(audioPlayerCommandsProvider.notifier);

    return Row(
      children: [
        const Icon(Icons.speed_rounded, size: 20),
        const SizedBox(width: 8),
        DropdownButton<double>(
          value: state.speed,
          underline: const SizedBox.shrink(),
          isDense: true,
          items: const [
            DropdownMenuItem(value: 0.5, child: Text('0.5×')),
            DropdownMenuItem(value: 0.75, child: Text('0.75×')),
            DropdownMenuItem(value: 1.0, child: Text('1×')),
            DropdownMenuItem(value: 1.25, child: Text('1.25×')),
            DropdownMenuItem(value: 1.5, child: Text('1.5×')),
            DropdownMenuItem(value: 2.0, child: Text('2×')),
          ],
          onChanged: (v) {
            if (v != null) commands.setSpeed(v);
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
