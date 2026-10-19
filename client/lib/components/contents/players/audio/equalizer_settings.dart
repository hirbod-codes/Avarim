// equalizer_settings.dart
//
// The user's equalizer settings: on / off and one gain (dB) per band. They are global (the same for every
// track), saved with shared_preferences, and applied to the player's engine whenever a track is opened
// (see AudioPlayerCommands.open). The equalizer panel edits them through [EqualizerStore].
//
// Bands differ per engine (Android: the device's, usually 5; web: 10), so the gains are stored per band
// index. If the number of bands changes (another device) missing gains count as 0 dB.

import 'dart:math' as math;

import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class EqualizerSettings {
  const EqualizerSettings({this.enabled = false, this.gains = const []});

  final bool enabled;

  /// dB per band, by band index. Shorter than the number of bands = the rest is flat.
  final List<double> gains;

  double gainAt(int band) => band < gains.length ? gains[band] : 0.0;

  EqualizerSettings copyWith({bool? enabled, List<double>? gains}) => EqualizerSettings(enabled: enabled ?? this.enabled, gains: gains ?? this.gains);
}

/// Ready-made curves. They are defined by frequency, so they work for any band layout.
enum EqualizerPreset {
  flat('Flat'),
  bass('Bass'),
  treble('Treble'),
  vocal('Vocal');

  const EqualizerPreset(this.label);

  final String label;

  static double _log2(double x) => math.log(x) / math.ln2;

  /// Suggested gain in dB for a band centred on [hz] (the caller clamps it to the band's range).
  double gainAt(double hz) {
    switch (this) {
      case EqualizerPreset.flat:
        return 0;
      case EqualizerPreset.bass:
        // +6 dB at 60 Hz and below, fading out by 500 Hz.
        final t = ((_log2(hz) - _log2(60)) / (_log2(500) - _log2(60))).clamp(0.0, 1.0).toDouble();
        return 6 * (1 - t);
      case EqualizerPreset.treble:
        // Nothing up to 2 kHz, +6 dB from 10 kHz.
        final t = ((_log2(hz) - _log2(2000)) / (_log2(10000) - _log2(2000))).clamp(0.0, 1.0).toDouble();
        return 6 * t;
      case EqualizerPreset.vocal:
        // A bump of about +5 dB around 2 kHz, one octave wide.
        final octaves = _log2(hz / 2000);
        return 5 * math.exp(-octaves * octaves);
    }
  }
}

class EqualizerStore {
  EqualizerStore._();

  static const _enabledKey = 'avarim.equalizer.enabled';
  static const _gainsKey = 'avarim.equalizer.gains';

  /// The current settings. Listen to it to keep a UI in sync.
  static final ValueNotifier<EqualizerSettings> settings = ValueNotifier(const EqualizerSettings());

  static Future<void>? _loading;

  /// Loads the saved settings (once).
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final gains = (prefs.getStringList(_gainsKey) ?? const <String>[]).map((g) => double.tryParse(g) ?? 0.0).toList();
      settings.value = EqualizerSettings(enabled: prefs.getBool(_enabledKey) ?? false, gains: gains);
    } catch (e) {
      debugPrint('EqualizerStore: loading failed: $e');
    }
  }

  /// Changes the settings. Pass `save: false` while a slider is being dragged and call [save] when it is released.
  static void update(EqualizerSettings next, {bool save = true}) {
    settings.value = next;
    if (save) EqualizerStore.save();
  }

  static Future<void> save() async {
    try {
      final s = settings.value;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, s.enabled);
      await prefs.setStringList(_gainsKey, [for (final g in s.gains) g.toString()]);
    } catch (e) {
      debugPrint('EqualizerStore: saving failed: $e');
    }
  }

  /// Applies the saved settings to [engine] (does nothing when the platform has no equalizer).
  static Future<void> applyTo(AppEqualizer? engine) async {
    if (engine == null) return;

    await ensureLoaded();
    final s = settings.value;

    try {
      final bands = await engine.bands();
      await engine.setEnabled(s.enabled);
      for (var i = 0; i < bands.length; i++) {
        await engine.setBandGain(i, s.gainAt(i).clamp(bands[i].minDb, bands[i].maxDb).toDouble());
      }
    } catch (e) {
      debugPrint('EqualizerStore: applying the settings failed: $e');
    }
  }
}
