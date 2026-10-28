import 'dart:async';
import 'dart:math' as math;

import 'package:avarim/api/models/audio.dart';
import 'package:avarim/app_config.dart';
import 'package:avarim/components/contents/players/audio/audio_info_panels.dart';
import 'package:avarim/components/contents/players/audio/audio_player_provider.dart';
import 'package:avarim/components/contents/players/audio/equalizer_panel.dart';
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

/// How far the radial gradient reaches, as a fraction of the distance from the cover art's
/// centre to the farthest corner of the screen. 1.0 = the last colour is reached exactly in
/// that corner; lower values reach the plain background colour sooner.
const kCoverGradientReach = 0.85;

/// Minimum contrast ratios the gradient must keep against the app's own colours, so that
/// the text and the primary-coloured controls stay comfortable to look at on any cover.
const kGradientMinContrastOnSurface = 7.0; // title, duration, labels  (WCAG AAA)
const kGradientMinContrastOnSurfaceVariant = 4.5; // artist, icons       (WCAG AA)
const kGradientMinContrastPrimary = 3.0; // play button, seek bar        (WCAG non-text AA)

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Darkens ([theme] is dark) or lightens ([theme] is light) [color] until the theme's text
/// colours and its primary colour all have enough contrast against it. The hue and
/// saturation are kept, so it still looks like the cover.
Color _fitToTheme(Color color, ColorScheme theme) {
  bool readable(Color c) =>
      _contrast(c, theme.onSurface) >= kGradientMinContrastOnSurface &&
      _contrast(c, theme.onSurfaceVariant) >= kGradientMinContrastOnSurfaceVariant &&
      _contrast(c, theme.primary) >= kGradientMinContrastPrimary;

  if (readable(color)) return color;

  final step = theme.brightness == Brightness.dark ? -0.02 : 0.02;
  var hsl = HSLColor.fromColor(color);
  for (var i = 0; i < 50 && !readable(hsl.toColor()); i++) {
    hsl = hsl.withLightness((hsl.lightness + step).clamp(0.0, 1.0));
  }
  return hsl.toColor();
}

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
    this.contentPadding = EdgeInsets.zero,
    this.showQueueControls = false,
    this.onPrevious,
    this.onNext,
    this.extraActions = const [],
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

  /// Safe area for the controls (status bar, overlaid buttons, nav bar). The background still fills everything.
  final EdgeInsets contentPadding;

  /// Show previous / next buttons next to the main controls (null callback = disabled button).
  final bool showQueueControls;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Extra buttons shown next to the playback speed button (the global player puts its queue button here).
  final List<Widget> extraActions;

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen> {
  StreamSubscription<AudioPlayerState>? _completionSub;
  AudioInfoPanel? _panel;
  bool _equalizerOpen = false;

  /// Gradient stops (top -> bottom) derived from the cover art; null until loaded
  /// or when the audio has no cover art.
  List<Color>? _gradient;
  Brightness? _gradientBrightness;

  // [_gradient] adjusted to the current theme's text / primary colours (see _fitToTheme); cached per theme.
  List<Color> _fitted = const [];
  ColorScheme? _fittedFor;

  // The radial gradient is centred on the cover art. Its position depends on the layout
  // (scaling, padding, screen size), so it is measured after layout.
  final _artKey = GlobalKey();
  final _backgroundKey = GlobalKey();
  Alignment _gradientCenter = const Alignment(0, -0.45); // until the first measurement
  double _gradientRadius = 1.0;
  BoxConstraints? _lastLayout;

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

  /// Finds the cover art's centre relative to the background and re-centres the gradient on it.
  void _measureGradientCenter() {
    if (!mounted) return;

    final art = _artKey.currentContext?.findRenderObject();
    final background = _backgroundKey.currentContext?.findRenderObject();
    if (art is! RenderBox || background is! RenderBox) return;
    if (!art.attached || !background.attached || !art.hasSize || !background.hasSize) return;

    final size = background.size;
    if (size.isEmpty) return;

    // Both boxes share the same transforms (dock slide, content scaling), so converting
    // through global coordinates gives the art's centre in the background's own pixels.
    final center = background.globalToLocal(art.localToGlobal(art.size.center(Offset.zero)));
    final alignment = Alignment(center.dx / size.width * 2 - 1, center.dy / size.height * 2 - 1);

    // RadialGradient.radius is a fraction of the shortest side; reach (a share of) the farthest corner.
    final farthest = [Offset.zero, Offset(size.width, 0), Offset(0, size.height), Offset(size.width, size.height)].map((c) => (c - center).distance).reduce(math.max);
    final radius = farthest * kCoverGradientReach / size.shortestSide;

    final unchanged = (alignment.x - _gradientCenter.x).abs() < 0.002 && (alignment.y - _gradientCenter.y).abs() < 0.002 && (radius - _gradientRadius).abs() < 0.002;
    if (unchanged) return;

    setState(() {
      _gradientCenter = alignment;
      _gradientRadius = radius;
    });
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
      setState(() {
        _gradient = [scheme.primaryContainer, scheme.tertiaryContainer, scheme.surface];
        _fittedFor = null; // re-fit to the theme in build
      });
    } catch (_) {
      // No cover art (or it failed to load): keep the plain background.
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(audioPlayerCommandsProvider.notifier);

    final waveform = widget.audio?.technical?.waveform ?? const <double>[];

    // At most one panel (lyrics / tags / technical / equalizer) replaces the album art at a time.
    final equalizer = notifier.equalizer; // null on platforms without an equalizer
    final equalizerOpen = _equalizerOpen && equalizer != null;
    final infoOpen = _panel != null && widget.audio != null;

    final themeScheme = Theme.of(context).colorScheme;
    if (_gradient != null && _fittedFor != themeScheme) {
      _fitted = [for (final c in _gradient!) _fitToTheme(c, themeScheme)];
      _fittedFor = themeScheme;
    }

    return AnimatedContainer(
      key: _backgroundKey,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      width: double.infinity,
      height: double.infinity,
      decoration: _gradient == null
          ? const BoxDecoration()
          : BoxDecoration(
              // Brightest at the centre of the cover art, fading to the plain surface colour outwards.
              gradient: RadialGradient(center: _gradientCenter, radius: _gradientRadius, colors: _fitted, stops: const [0.0, 0.5, 1.0]),
            ),
      // Transparent Material: gives buttons / sliders a surface whose splashes are drawn ABOVE the gradient.
      child: Material(
        type: MaterialType.transparency,
        child: StreamBuilder<AudioPlayerState>(
      stream: notifier.stateStream,
      initialData: notifier.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const AudioPlayerState();
        if (state.hasError) {
          return _ErrorView(message: state.error ?? 'Unknown error');
        }
        return Padding(
          padding: widget.contentPadding,
          child: LayoutBuilder(
            builder: (context, box) {
              // The layout changed -> re-measure where the cover art ended up.
              if (_lastLayout != box) {
                _lastLayout = box;
                WidgetsBinding.instance.addPostFrameCallback((_) => _measureGradientCenter());
              }
              // The controls take the height they need (no fixed layout height to outgrow). If that is
              // more than is available they are scaled down to fit, never up; if it is less they are
              // centered vertically. The background / gradient is outside this and always fills everything.
              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: box.maxWidth,
                    child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kAudioPlayerContentMaxWidth),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                      visible: !infoOpen && !equalizerOpen,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Column(
                        children: [
                          const SizedBox(height: 24),
                          Container(
                            key: _artKey,
                            constraints: BoxConstraints(maxHeight: 300),
                            child: _AlbumArt(audioId: widget.audioId, accessToken: widget.accessToken),
                          ),
                          const SizedBox(height: 40),
                          // Full width, so that the text starts at the left edge instead of being centered.
                          SizedBox(
                            width: double.infinity,
                            child: _TrackInfo(title: state.title, artist: state.artist),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                    if (infoOpen)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: AudioInfoPanelView(key: ValueKey(_panel), audio: widget.audio!, panel: _panel!, onClose: () => setState(() => _panel = null)),
                        ),
                      ),
                    if (equalizerOpen)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: EqualizerPanel(engine: equalizer, onClose: () => setState(() => _equalizerOpen = false)),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                children: [
                  Row(
                    children: [
                      if (widget.audio != null)
                        AudioInfoButtons(
                          audio: widget.audio!,
                          selected: _panel,
                          onSelected: (p) => setState(() {
                            _panel = p;
                            if (p != null) _equalizerOpen = false;
                          }),
                        ),
                      if (equalizer != null)
                        IconButton(
                          tooltip: 'Equalizer',
                          visualDensity: VisualDensity.compact,
                          isSelected: equalizerOpen,
                          icon: const Icon(Icons.equalizer),
                          style: IconButton.styleFrom(
                            foregroundColor: equalizerOpen ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                            backgroundColor: equalizerOpen ? Theme.of(context).colorScheme.primaryContainer : null,
                          ),
                          onPressed: () => setState(() {
                            _equalizerOpen = !_equalizerOpen;
                            if (_equalizerOpen) _panel = null;
                          }),
                        ),
                      const Spacer(),
                      ...widget.extraActions,
                      _SpeedControls(state: state),
                    ],
                  ),
                  // Waveform when the audio has one, otherwise the plain slider.
                  if (waveform.isNotEmpty) _WaveformSeekBar(state: state, waveform: waveform) else _SeekBar(state: state),
                ],
              ),
              const SizedBox(height: 24),
              _MainControls(state: state, showQueueControls: widget.showQueueControls, onPrevious: widget.onPrevious, onNext: widget.onNext),
              const SizedBox(height: 24),
              _VolumeControls(state: state),
              const SizedBox(height: 32),
            ],
          ),
              ),
            ),
          ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
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
            inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24),
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
// Waveform seek bar
// ---------------------------------------------------------------------------

/// How much the quiet / loud difference of the waveform is exaggerated. 1 = as stored (heavily
/// compressed music then looks like a flat block), 2 = clearer shape, higher = spikier.
const kWaveformContrast = 2.0;

const kWaveformHeight = 64.0;

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Seek bar drawn from `technical.waveform` (values 0..1): played part in the primary colour, the
/// buffered part and the rest dimmer. Tap or drag anywhere on it to seek.
class _WaveformSeekBar extends ConsumerStatefulWidget {
  const _WaveformSeekBar({required this.state, required this.waveform});

  final AudioPlayerState state;
  final List<double> waveform;

  @override
  ConsumerState<_WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends ConsumerState<_WaveformSeekBar> {
  /// 0..1 while the user drags (the bar follows the finger before the player catches up).
  double? _dragFraction;

  double _fractionAt(double dx, double width) => width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0);

  void _seek(double fraction) {
    final target = Duration(milliseconds: (fraction * widget.state.duration.inMilliseconds).round());
    ref.read(audioPlayerCommandsProvider.notifier).seek(target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = widget.state;
    final progress = _dragFraction ?? player.progress;
    final shownPosition = _dragFraction == null ? player.position : Duration(milliseconds: (_dragFraction! * player.duration.inMilliseconds).round());

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            return Semantics(
              slider: true,
              label: 'Seek',
              value: '${_formatDuration(shownPosition)} of ${_formatDuration(player.duration)}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _seek(_fractionAt(d.localPosition.dx, width)),
                onHorizontalDragStart: (d) => setState(() => _dragFraction = _fractionAt(d.localPosition.dx, width)),
                onHorizontalDragUpdate: (d) => setState(() => _dragFraction = _fractionAt(d.localPosition.dx, width)),
                onHorizontalDragEnd: (_) {
                  final fraction = _dragFraction;
                  setState(() => _dragFraction = null);
                  if (fraction != null) _seek(fraction);
                },
                onHorizontalDragCancel: () => setState(() => _dragFraction = null),
                child: SizedBox(
                  width: double.infinity,
                  height: kWaveformHeight,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      waveform: widget.waveform,
                      progress: progress,
                      buffered: player.bufferedProgress,
                      playedColor: theme.colorScheme.primary,
                      bufferedColor: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                      idleColor: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(shownPosition), style: theme.textTheme.labelMedium),
              Text(_formatDuration(player.duration), style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.waveform,
    required this.progress,
    required this.buffered,
    required this.playedColor,
    required this.bufferedColor,
    required this.idleColor,
  });

  final List<double> waveform;
  final double progress;
  final double buffered;
  final Color playedColor;
  final Color bufferedColor;
  final Color idleColor;

  static const _barWidth = 3.0;
  static const _barGap = 2.0;
  static const _minBarHeight = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || waveform.isEmpty) return;

    // As many bars as fit; each one shows the loudest sample of its slice of the waveform.
    final count = math.max(1, ((size.width + _barGap) / (_barWidth + _barGap)).floor());
    final spacing = count > 1 ? (size.width - _barWidth) / (count - 1) : 0.0;
    final midY = size.height / 2;
    final paint = Paint()
      ..strokeWidth = _barWidth
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < count; i++) {
      final from = (i * waveform.length / count).floor();
      final to = math.min(waveform.length, math.max(from + 1, ((i + 1) * waveform.length / count).ceil()));

      var peak = 0.0;
      for (var j = from; j < to; j++) {
        peak = math.max(peak, waveform[j]);
      }

      final amplitude = math.pow(peak.clamp(0.0, 1.0), kWaveformContrast).toDouble();
      final barHeight = math.max(_minBarHeight, amplitude * size.height);

      final x = _barWidth / 2 + i * spacing;
      final fraction = x / size.width;
      paint.color = fraction <= progress ? playedColor : (fraction <= buffered ? bufferedColor : idleColor);

      // The round caps add half a bar width at each end.
      final half = math.max(0.0, barHeight - _barWidth) / 2;
      canvas.drawLine(Offset(x, midY - half), Offset(x, midY + half), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      !identical(old.waveform, waveform) ||
      old.progress != progress ||
      old.buffered != buffered ||
      old.playedColor != playedColor ||
      old.bufferedColor != bufferedColor ||
      old.idleColor != idleColor;
}

// ---------------------------------------------------------------------------
// Main controls
// ---------------------------------------------------------------------------

/// Below this screen width the main controls show previous / next track instead of -10 / +10 seconds
/// (the seek bar covers moving inside the track).
const kCompactPlayerWidth = 600.0;

class _MainControls extends ConsumerWidget {
  const _MainControls({required this.state, this.showQueueControls = false, this.onPrevious, this.onNext});
  final AudioPlayerState state;
  final bool showQueueControls;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(audioPlayerCommandsProvider.notifier);
    final isLoading = state.isLoading || state.isBuffering;
    final compact = MediaQuery.sizeOf(context).width < kCompactPlayerWidth;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (compact)
          // Always there on small screens (disabled when there is no queue / no previous track).
          IconButton(iconSize: 44, tooltip: 'Previous', onPressed: showQueueControls ? onPrevious : null, icon: const Icon(Icons.skip_previous_rounded))
        else ...[
          if (showQueueControls) IconButton(iconSize: 36, tooltip: 'Previous', onPressed: onPrevious, icon: const Icon(Icons.skip_previous_rounded)),
          IconButton(iconSize: 40, onPressed: () => commands.skipBackward(), icon: const Icon(Icons.replay_10_rounded)),
        ],
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
        if (compact)
          IconButton(iconSize: 44, tooltip: 'Next', onPressed: showQueueControls ? onNext : null, icon: const Icon(Icons.skip_next_rounded))
        else ...[
          IconButton(iconSize: 40, onPressed: () => commands.skipForward(), icon: const Icon(Icons.forward_10_rounded)),
          if (showQueueControls) IconButton(iconSize: 36, tooltip: 'Next', onPressed: onNext, icon: const Icon(Icons.skip_next_rounded)),
        ],
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
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24)),
            child: Slider(value: state.volume.clamp(0.0, 1.0), onChanged: (v) => commands.setVolume(v)),
          ),
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

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  static String _label(double speed) => '${speed == speed.roundToDouble() ? speed.toInt() : speed}×';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(audioPlayerCommandsProvider.notifier);

    // MenuAnchor (not DropdownButton / PopupMenuButton): those open their menu as a route, and routes are
    // drawn underneath the global player, so the menu would be hidden behind it. MenuAnchor's menu lives
    // in the overlay, above the player.
    return MenuAnchor(
      menuChildren: [
        for (final speed in _speeds)
          MenuItemButton(
            leadingIcon: speed == state.speed ? const Icon(Icons.check, size: 18) : const SizedBox(width: 18),
            onPressed: () => commands.setSpeed(speed),
            child: Text(_label(speed)),
          ),
      ],
      builder: (context, controller, child) => TextButton.icon(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Theme.of(context).colorScheme.onSurface),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.speed_rounded, size: 20),
        label: Text(_label(state.speed)),
      ),
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
