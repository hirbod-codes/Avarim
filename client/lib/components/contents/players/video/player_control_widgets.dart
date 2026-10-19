import 'package:avarim/components/contents/players/video/player_interface.dart';
import 'package:flutter/material.dart';

class PlayerControls extends StatelessWidget {
  final AppVideoPlayer player;
  final PlayerState state;
  final Function? onTouch;

  const PlayerControls({super.key, required this.state, required this.player, this.onTouch});

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case PlayerStatus.loading:
        return const _ControlsShell(child: _LoadingIndicator());

      case PlayerStatus.error:
        return _ControlsShell(child: _ErrorLabel(message: 'Error encountered while playing video'));

      default:
        return _Controls(state: state, player: player, onTouch: onTouch);
    }
  }
}

// ---------------------------------------------------------------------------
// Translucent shell that sits at the bottom of the Stack
// ---------------------------------------------------------------------------

class _ControlsShell extends StatelessWidget {
  final Widget child;

  const _ControlsShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
      ),
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 12), child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// Main controls content
// ---------------------------------------------------------------------------

class _Controls extends StatelessWidget {
  final AppVideoPlayer player;
  final PlayerState state;
  final Function? onTouch;

  const _Controls({required this.state, required this.player, this.onTouch});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Seek bar + times
        Row(
          children: [
            _TimeLabel(state.position),
            Expanded(
              child: _SeekBar(
                state: state,
                onSeek: (d) async {
                  player.seek(d);
                  if (onTouch != null) onTouch!();
                },
              ),
            ),
            _TimeLabel(state.duration),
          ],
        ),
        const SizedBox(height: 4),
        // Play/pause + volume
        Row(
          children: [
            _PlayPauseButton(
              state: state,
              onTap: () {
                player.togglePlayPause();
                if (onTouch != null) onTouch!();
              },
            ),
            const SizedBox(width: 8),
            _BufferingIndicator(state: state),
            const Spacer(),
            _VolumeControl(
              volume: state.volume,
              onChanged: (v) async {
                player.setVolume(v);
                if (onTouch != null) onTouch!();
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Individual control widgets
// ---------------------------------------------------------------------------

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.state, required this.onTap});
  final PlayerState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state.status) {
      PlayerStatus.playing => Icons.pause_rounded,
      PlayerStatus.paused => Icons.play_arrow_rounded,
      PlayerStatus.ended => Icons.replay_rounded,
      _ => Icons.play_arrow_rounded,
    };

    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 36),
      padding: EdgeInsets.zero,
    );
  }
}

class _BufferingIndicator extends StatelessWidget {
  const _BufferingIndicator({required this.state});
  final PlayerState state;

  @override
  Widget build(BuildContext context) {
    if (state.status != PlayerStatus.buffering) return const SizedBox.shrink();
    return const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70));
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.state, required this.onSeek});
  final PlayerState state;
  final Future<void> Function(Duration) onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _draggingValue;

  @override
  Widget build(BuildContext context) {
    final progress = _draggingValue ?? widget.state.progress;
    final bufferedProgress = widget.state.duration.inMilliseconds > 0 ? widget.state.buffered.inMilliseconds / widget.state.duration.inMilliseconds : 0.0;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: Colors.white,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayColor: Colors.white24,
        secondaryActiveTrackColor: Colors.white38,
      ),
      child: Slider(
        value: progress.clamp(0.0, 1.0),
        secondaryTrackValue: bufferedProgress.clamp(0.0, 1.0),
        onChangeStart: (_) => setState(() => _draggingValue = progress),
        onChanged: (v) => setState(() => _draggingValue = v),
        onChangeEnd: (v) {
          setState(() => _draggingValue = null);
          final target = Duration(milliseconds: (v * widget.state.duration.inMilliseconds).round());
          widget.onSeek(target);
        },
      ),
    );
  }
}

class _VolumeControl extends StatefulWidget {
  const _VolumeControl({required this.volume, required this.onChanged});
  final double volume;
  final Future<void> Function(double) onChanged;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_expanded)
          SizedBox(
            width: 80,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: Colors.white24,
              ),
              child: Slider(value: widget.volume.clamp(0.0, 1.0), onChanged: widget.onChanged),
            ),
          ),
        IconButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(
            widget.volume == 0
                ? Icons.volume_off_rounded
                : widget.volume < 0.5
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded,
            color: Colors.white,
            size: 24,
          ),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel(this.duration);
  final Duration duration;

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Text(_format(duration), style: const TextStyle(color: Colors.white70, fontSize: 12));
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(color: Colors.white54));
  }
}

class _ErrorLabel extends StatelessWidget {
  const _ErrorLabel({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
