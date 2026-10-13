// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_player_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AudioPlayerCommands)
final audioPlayerCommandsProvider = AudioPlayerCommandsProvider._();

final class AudioPlayerCommandsProvider
    extends $NotifierProvider<AudioPlayerCommands, void> {
  AudioPlayerCommandsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'audioPlayerCommandsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$audioPlayerCommandsHash();

  @$internal
  @override
  AudioPlayerCommands create() => AudioPlayerCommands();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$audioPlayerCommandsHash() =>
    r'217fe934e31896564f26f26a7034c963df510779';

abstract class _$AudioPlayerCommands extends $Notifier<void> {
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
