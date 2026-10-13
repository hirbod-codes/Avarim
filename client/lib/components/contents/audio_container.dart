import 'dart:async';

import 'package:avarim/api/controllers/audio_controller.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/app_config.dart';
import 'package:avarim/auth/token_storage.dart';
import 'package:avarim/components/contents/players/audio/audio_player_provider.dart';
import 'package:avarim/components/contents/players/audio/audio_player_screen.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/theme/theme_radius.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AudioContainer extends ConsumerStatefulWidget {
  final String audioId;

  /// Height of the player area (the floating panel passes a screen-aware value).
  final double height;

  /// Defaults to the app's medium radius; the floating panel passes
  /// [BorderRadius.zero] because the panel itself is already rounded.
  final BorderRadius? borderRadius;

  const AudioContainer({super.key, required this.audioId, this.height = 700, this.borderRadius});

  @override
  ConsumerState<AudioContainer> createState() => _AudioContainerState();
}

class _AudioContainerState extends ConsumerState<AudioContainer> {
  String? _token;
  Audio? _audio;
  String? _url;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    initiate();
  }

  Future<void> initiate() async {
    try {
      final audio = await ref.read(audioControllerProvider).get(audioId: widget.audioId);
      if (!mounted) return;

      final storage = ref.read(tokenStorageProvider);

      final token = await storage.getAccessToken();
      if (!mounted) return;

      String? signedToken;
      if (kIsWeb) {
        signedToken = await ref.read(audioControllerProvider).getSignedToken(audioId: widget.audioId);
        if (!mounted) return;
      }

      setState(() {
        if (token != null && token != '') {
          _token = token;
        }
        _audio = audio;
        _url = '${AppConfig.apiUrl}/api/audio/file${kIsWeb ? '/web' : ''}/${_audio!.id}${signedToken == null ? '' : '/$signedToken'}';
        _loading = false;
      });
    } catch (e) {
      talker.error('caught error while trying to fetch audio', e);
      _handleError(e);
    }
  }

  FutureOr<Null> _handleError(dynamic e) {
    if (!mounted) return null;

    NotificationService.showError(message: AppLocalizations.of(context)!.audio_fetch_failed);

    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary))],
      );
    }

    AppLocalizations l10n = AppLocalizations.of(context)!;

    if (_audio == null) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [Text(l10n.audio_not_found)]),
      );
    }
    if (_token == null) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [Text(l10n.unauthenticated)]),
      );
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(AppRadius.md),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      clipBehavior: Clip.antiAlias,
      child: ProviderScope(
        overrides: [audioPlayerCommandsProvider],
        // TODO(autoplay): pass an autoPlay flag here once AudioPlayerScreen supports one.
        child: AudioPlayerScreen(audioId: _audio!.id, url: _url!, headers: {'Authorization': 'Bearer ${_token!}'}, accessToken: _token!, title: _audio!.title),
      ),
    );
  }
}
