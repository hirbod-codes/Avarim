// equalizer_panel.dart  (next to audio_player_screen.dart)
//
// The equalizer panel the player opens in place of the album art: an on/off switch, a few presets and one
// vertical slider per band. Moving a slider turns the equalizer on. Settings are shared by every track and
// saved (see equalizer_settings.dart); the engine is updated live.

import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:avarim/components/contents/players/audio/equalizer_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

String _hzLabel(double hz) {
  if (hz < 1000) return '${hz.round()}';
  final k = hz / 1000;
  return '${k == k.roundToDouble() ? k.round() : k.toStringAsFixed(1)}k';
}

String _dbLabel(double db) {
  final rounded = db.round();
  return rounded > 0 ? '+$rounded' : '$rounded';
}

class EqualizerPanel extends StatefulWidget {
  const EqualizerPanel({super.key, required this.engine, required this.onClose});

  final AppEqualizer engine;
  final VoidCallback onClose;

  @override
  State<EqualizerPanel> createState() => _EqualizerPanelState();
}

class _EqualizerPanelState extends State<EqualizerPanel> {
  late final Future<List<EqualizerBand>> _bands = _loadBands();

  Future<List<EqualizerBand>> _loadBands() async {
    await EqualizerStore.ensureLoaded();
    return widget.engine.bands();
  }

  /// Engine calls are fire-and-forget while sliding; a failure must not crash the UI.
  void _fire(Future<void> call) {
    call.catchError((Object e) => debugPrint('Equalizer: $e'));
  }

  void _setEnabled(bool enabled) {
    EqualizerStore.update(EqualizerStore.settings.value.copyWith(enabled: enabled));
    _fire(widget.engine.setEnabled(enabled));
  }

  void _dragBand(List<EqualizerBand> bands, int index, double db) {
    final s = EqualizerStore.settings.value;
    final gains = [for (var i = 0; i < bands.length; i++) i == index ? db : s.gainAt(i)];

    EqualizerStore.update(s.copyWith(enabled: true, gains: gains), save: false);
    _fire(widget.engine.setEnabled(true));
    _fire(widget.engine.setBandGain(index, db));
  }

  void _applyPreset(List<EqualizerBand> bands, EqualizerPreset preset) {
    final s = EqualizerStore.settings.value;
    final gains = [for (final b in bands) preset.gainAt(b.centerHz).clamp(b.minDb, b.maxDb).toDouble()];
    final enabled = preset == EqualizerPreset.flat ? s.enabled : true;

    EqualizerStore.update(s.copyWith(enabled: enabled, gains: gains));
    _fire(widget.engine.setEnabled(enabled));
    for (var i = 0; i < gains.length; i++) {
      _fire(widget.engine.setBandGain(i, gains[i]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ValueListenableBuilder<EqualizerSettings>(
        valueListenable: EqualizerStore.settings,
        builder: (context, settings, _) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('Equalizer', style: theme.textTheme.titleMedium)),
                    Switch(value: settings.enabled && widget.engine.available, onChanged: widget.engine.available ? _setEnabled : null),
                    IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: widget.onClose),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: widget.engine.available
                    ? FutureBuilder<List<EqualizerBand>>(
                        future: _bands,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) return const Center(child: Text('The equalizer could not be read'));

                          final bands = snapshot.data;
                          if (bands == null) return const Center(child: CircularProgressIndicator());

                          return _Bands(
                            bands: bands,
                            settings: settings,
                            onPreset: (preset) => _applyPreset(bands, preset),
                            onDrag: (index, db) => _dragBand(bands, index, db),
                            onDragEnd: EqualizerStore.save,
                          );
                        },
                      )
                    : const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('The equalizer is not available for this audio.', textAlign: TextAlign.center),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Bands extends StatelessWidget {
  const _Bands({required this.bands, required this.settings, required this.onPreset, required this.onDrag, required this.onDragEnd});

  final List<EqualizerBand> bands;
  final EqualizerSettings settings;
  final ValueChanged<EqualizerPreset> onPreset;
  final void Function(int index, double db) onDrag;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: theme.colorScheme.onSurface.withValues(alpha: 0.24),
    );

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final preset in EqualizerPreset.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(label: Text(preset.label), onPressed: () => onPreset(preset)),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                for (var i = 0; i < bands.length; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Text(_dbLabel(settings.gainAt(i)), style: theme.textTheme.labelSmall),
                        Expanded(
                          // Rotated a quarter turn so the slider is vertical, loud at the top.
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: sliderTheme,
                              child: Slider(
                                min: bands[i].minDb,
                                max: bands[i].maxDb,
                                divisions: (bands[i].maxDb - bands[i].minDb).round(),
                                value: settings.gainAt(i).clamp(bands[i].minDb, bands[i].maxDb).toDouble(),
                                onChanged: (db) => onDrag(i, db),
                                onChangeEnd: (_) => onDragEnd(),
                              ),
                            ),
                          ),
                        ),
                        Text(_hzLabel(bands[i].centerHz), style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
