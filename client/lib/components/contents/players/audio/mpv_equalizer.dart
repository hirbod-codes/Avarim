// mpv_equalizer.dart
//
// The equalizer of the media_kit engine: a chain of ffmpeg `equalizer` filters set as mpv's `af` property.
// It has the same 10 octave bands as the web engine (31 Hz ... 16 kHz, +-12 dB), so the user's settings
// mean the same everywhere. Only bands that aren't flat are put in the chain, and nothing at all when the
// equalizer is off.
//
// Changes are collected for a moment and sent together (dragging a slider changes the gain many times a second,
// and every `af` change rebuilds mpv's filter chain). If mpv refuses the chain (a libmpv build without the
// `equalizer` filter), [available] turns false and the panel says so.

import 'dart:async';

import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:avarim/lib/talker.dart';
import 'package:media_kit/media_kit.dart';

class MpvEqualizer implements AppEqualizer {
  MpvEqualizer(this._player);

  final Player _player;

  static const _centers = [31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];
  static const _rangeDb = 12.0;

  bool _available = true;
  bool _enabled = false;
  final List<double> _gains = List.filled(_centers.length, 0.0);

  Timer? _debounce;
  String _applied = ''; // the chain mpv has now

  @override
  bool get available => _available;

  @override
  Future<List<EqualizerBand>> bands() async => [for (final hz in _centers) EqualizerBand(centerHz: hz, minDb: -_rangeDb, maxDb: _rangeDb)];

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    _schedule();
  }

  @override
  Future<void> setBandGain(int index, double db) async {
    if (index < 0 || index >= _gains.length) return;
    _gains[index] = db.clamp(-_rangeDb, _rangeDb).toDouble();
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 80), _apply);
  }

  /// mpv's `--af` value, e.g. `lavfi=[equalizer=f=125:t=o:w=1:g=3.0,...]`. Empty = no filter.
  String _chain() {
    if (!_enabled) return '';

    final filters = <String>[
      for (var i = 0; i < _centers.length; i++)
        if (_gains[i].abs() >= 0.05) 'equalizer=f=${_centers[i].toStringAsFixed(0)}:t=o:w=1:g=${_gains[i].toStringAsFixed(1)}',
    ];
    return filters.isEmpty ? '' : 'lavfi=[${filters.join(',')}]';
  }

  Future<void> _apply() async {
    final chain = _chain();
    if (chain == _applied) return;

    try {
      final platform = _player.platform;
      if (platform == null) return;
      // `dynamic`: setProperty only exists on the native player (the web stub has none).
      await (platform as dynamic).setProperty('af', chain);
      _applied = chain;
    } catch (e, st) {
      talker.error('could not set the mpv audio filter, the equalizer is not available here', e, st);
      _available = false;
    }
  }

  void dispose() => _debounce?.cancel();
}
