import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:avarim/auth/token_storage.dart';
import 'package:avarim/app_config.dart';

class TTSButton extends ConsumerStatefulWidget {
  final String word;

  const TTSButton({super.key, required this.word});

  @override
  ConsumerState<TTSButton> createState() => _TTSButton();
}

class _TTSButton extends ConsumerState<TTSButton> {
  final AudioPlayer _player = AudioPlayer();
  bool _isLoading = false;
  bool _isPlaying = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    initiate();
  }

  Future<void> initiate() async {
    final storage = ref.read(tokenStorageProvider);

    final token = await storage.getAccessToken();
    if (!mounted) return;

    setState(() {
      _token = token;
    });

    _player.playerStateStream.listen((state) {
      if (!mounted) return;

      setState(() {
        _isPlaying = state.playing && state.processingState != ProcessingState.completed;
      });

      if (state.processingState == ProcessingState.completed) _player.stop();
    });
  }

  Future<void> _playPronunciation() async {
    if (_isLoading || _isPlaying || _token == null) return;

    setState(() => _isLoading = true);

    try {
      // The _player doesn't send headers in web platform so it has go though query parameters.
      final uri = Uri.parse('${AppConfig.apiUrl}/api/audio/tts?text=${Uri.encodeComponent(widget.word)}&authToken=$_token');

      await _player.setUrl(uri.toString());
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (e) {
      if (mounted) {
        AppLocalizations l10n = AppLocalizations.of(context)!;
        NotificationService.showError(message: l10n.tts_failed_to_play_pronunciation);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations l10n = AppLocalizations.of(context)!;

    return IconButton(
      icon: _isLoading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(_isPlaying ? Icons.volume_up : Icons.volume_up_outlined),
      tooltip: l10n.tts_hear_pronunciation,
      onPressed: _isLoading ? null : _playPronunciation,
    );
  }
}
