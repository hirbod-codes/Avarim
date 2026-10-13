// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_player_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(videoPlayer)
final videoPlayerProvider = VideoPlayerProvider._();

final class VideoPlayerProvider
    extends $FunctionalProvider<AppVideoPlayer, AppVideoPlayer, AppVideoPlayer>
    with $Provider<AppVideoPlayer> {
  VideoPlayerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'videoPlayerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$videoPlayerHash();

  @$internal
  @override
  $ProviderElement<AppVideoPlayer> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppVideoPlayer create(Ref ref) {
    return videoPlayer(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppVideoPlayer value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppVideoPlayer>(value),
    );
  }
}

String _$videoPlayerHash() => r'f627811825f7255d1bd064eddcdd37e154c8d564';

@ProviderFor(videoController)
final videoControllerProvider = VideoControllerProvider._();

final class VideoControllerProvider
    extends
        $FunctionalProvider<
          VideoController?,
          VideoController?,
          VideoController?
        >
    with $Provider<VideoController?> {
  VideoControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'videoControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$videoControllerHash();

  @$internal
  @override
  $ProviderElement<VideoController?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VideoController? create(Ref ref) {
    return videoController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VideoController? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VideoController?>(value),
    );
  }
}

String _$videoControllerHash() => r'8b95292a041e7f6d45eee84496240ac326f19345';

@ProviderFor(playerState)
final playerStateProvider = PlayerStateProvider._();

final class PlayerStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<PlayerState>,
          PlayerState,
          Stream<PlayerState>
        >
    with $FutureModifier<PlayerState>, $StreamProvider<PlayerState> {
  PlayerStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playerStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playerStateHash();

  @$internal
  @override
  $StreamProviderElement<PlayerState> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<PlayerState> create(Ref ref) {
    return playerState(ref);
  }
}

String _$playerStateHash() => r'405078b176421d1f54a442fce9b2268bdf31158c';

@ProviderFor(VideoPlayerCommands)
final videoPlayerCommandsProvider = VideoPlayerCommandsProvider._();

final class VideoPlayerCommandsProvider
    extends $NotifierProvider<VideoPlayerCommands, void> {
  VideoPlayerCommandsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'videoPlayerCommandsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$videoPlayerCommandsHash();

  @$internal
  @override
  VideoPlayerCommands create() => VideoPlayerCommands();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$videoPlayerCommandsHash() =>
    r'6eebe086906ec840a8d3ae8898cc6875324c565d';

abstract class _$VideoPlayerCommands extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
