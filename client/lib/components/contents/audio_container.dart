import 'dart:async';

import 'package:avarim/api/controllers/audio_controller.dart';
import 'package:avarim/api/providers/audio_links.dart';
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

  /// Start playing as soon as the track is loaded (used by the global player).
  final bool autoPlay;

  /// Called when the track finishes (used by the global player to advance the queue).
  final VoidCallback? onCompleted;

  /// Safe area for the player's content (the background / gradient still fills everything).
  final EdgeInsets contentPadding;

  /// Show previous / next buttons in the player. A null callback shows the button disabled.
  final bool showQueueControls;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Extra buttons the player shows next to its playback speed button.
  final List<Widget> extraActions;

  /// When true (default) the container creates its own player (its own Riverpod scope).
  /// The global dock passes false because it provides the scope itself, so that the mini
  /// bar can control the same player.
  final bool ownPlayerScope;

  /// Pass `double.infinity` to fill the space the parent gives (tight constraints required).
  const AudioContainer({
    super.key,
    required this.audioId,
    this.height = 700,
    this.borderRadius,
    this.autoPlay = false,
    this.onCompleted,
    this.contentPadding = EdgeInsets.zero,
    this.showQueueControls = false,
    this.onPrevious,
    this.onNext,
    this.extraActions = const [],
    this.ownPlayerScope = true,
  });

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

  /// "Artist A, Artist B", or null. An audio's artists are resolved from its links (see audioArtistsProvider),
  /// not read from its tags. Call it from build: the label appears once they are loaded.
  String? _artistLabel(Audio audio) => artistsLabel(ref.watch(audioArtistsProvider(audio.id)).value);

  /// With a fixed height the placeholder states keep their old compact layout;
  /// when asked to fill the parent (infinite height) they are centered in it.
  Widget _placeholder(Widget child) => widget.height.isFinite ? child : SizedBox.expand(child: Center(child: child));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return _placeholder(
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary))],
        ),
      );
    }

    AppLocalizations l10n = AppLocalizations.of(context)!;

    if (_audio == null) {
      return _placeholder(
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [Text(l10n.audio_not_found)]),
        ),
      );
    }
    if (_token == null) {
      return _placeholder(
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [Text(l10n.unauthenticated)]),
        ),
      );
    }

    final screen = AudioPlayerScreen(
      audioId: _audio!.id,
      url: _url!,
      headers: {'Authorization': 'Bearer ${_token!}'},
      accessToken: _token!,
      title: _audio!.title,
      artist: _artistLabel(_audio!),
      audio: _audio,
      autoPlay: widget.autoPlay,
      onCompleted: widget.onCompleted,
      contentPadding: widget.contentPadding,
      showQueueControls: widget.showQueueControls,
      onPrevious: widget.onPrevious,
      onNext: widget.onNext,
      extraActions: widget.extraActions,
    );

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(AppRadius.md),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.ownPlayerScope ? ProviderScope(overrides: [audioPlayerCommandsProvider], child: screen) : screen,
    );
  }
}
