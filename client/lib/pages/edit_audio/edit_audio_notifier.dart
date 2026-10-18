// edit_audio_notifier.dart
//
// Logic behind EditAudioPage: open an existing audio, or follow a queued upload
// (poll until it is processed, then load it), and save edits.
//
// The API methods return ApiCallResult. A failure there was already shown to the user as a
// toast (or is silent on purpose and shown on the page), so nothing here toasts it again.

import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/pages/edit_audio/edit_audio_api.dart';
import 'package:avarim/pages/edit_audio/edit_audio_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kPollInterval = Duration(seconds: 5);

/// Gives up waiting after this many polls (120 x 5s = 10 minutes).
const kMaxPollAttempts = 120;

class AudioUploadNotifier extends Notifier<UploadState> {
  Timer? _timer;
  CancelToken? _token;
  bool _checking = false;
  int _attempts = 0;
  int _consecutiveErrors = 0;

  AudioUploadApi get _api => ref.read(audioUploadApiProvider);

  @override
  UploadState build() {
    ref.onDispose(_stop);
    return const UploadState();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _token?.cancel();
    _token = null;
    _checking = false;
  }

  /// Back to the start (also cancels an in-flight upload / polling; a job
  /// already queued on the server keeps running).
  void reset() {
    _stop();
    state = const UploadState();
  }

  /// Opens an existing audio for editing.
  Future<void> openExisting(String audioId) async {
    _stop();
    final token = _token = CancelToken();
    state = UploadState(phase: UploadPhase.loading, id: audioId, existing: true);

    final result = await _api.getInfo(audioId, cancelToken: token);
    if (!ref.mounted || token.isCancelled) return;
    _showInfo(result);
  }

  /// Called once the upload was accepted by the server (the dialog's result is `{ id }`).
  void startProcessing(String id) {
    _stop();
    state = UploadState(phase: UploadPhase.processing, id: id);
    _startPolling();
  }

  /// After a failure: load the audio again / check the queued job again.
  void resume() {
    final id = state.id;
    if (id == null) return reset();

    if (state.existing) {
      unawaited(openExisting(id));
      return;
    }

    state = state.copyWith(phase: UploadPhase.processing, clearError: true);
    _startPolling();
    unawaited(_poll());
  }

  void _startPolling() {
    _timer?.cancel();
    _attempts = 0;
    _consecutiveErrors = 0;
    _timer = Timer.periodic(kPollInterval, (_) => unawaited(_poll()));
  }

  Future<void> _poll() async {
    final id = state.id;
    if (_checking || id == null || state.phase != UploadPhase.processing) return;

    _checking = true;
    final token = _token = CancelToken();
    try {
      _attempts++;
      final result = await _api.isUploadFinished(id, cancelToken: token);
      if (!ref.mounted || token.isCancelled) return;

      if (result case ApiCallFailure(:final message)) {
        // A flaky network gets a couple of retries before the job is reported as failed.
        _consecutiveErrors++;
        if (_consecutiveErrors >= 3) {
          _timer?.cancel();
          _fail(message);
        }
        return;
      }
      _consecutiveErrors = 0;

      if (result.isSuccess) {
        // Finished.
        _timer?.cancel();
        final info = await _api.getInfo(id, cancelToken: token);
        if (!ref.mounted || token.isCancelled) return;
        _showInfo(info);
      } else if (_attempts >= kMaxPollAttempts) {
        _timer?.cancel();
        _fail('Timed out waiting for the upload to finish processing');
      }
    } finally {
      _checking = false;
    }
  }

  /// Shows the editor for a loaded audio, or the failure.
  void _showInfo(ApiCallResult<Map<String, dynamic>> result) {
    if (result case ApiCallFailure(:final message)) {
      _fail(message);
      return;
    }

    final audio = result.dataOrNull;
    if (audio == null) {
      _fail('The server did not return the audio.');
      return;
    }
    state = state.copyWith(phase: UploadPhase.editing, audio: audio);
  }

  void _fail(String message) {
    state = state.copyWith(phase: UploadPhase.failed, error: message);
  }

  /// Sends only what changed: one PATCH each for the title, artists, album and lyrics (they have their own
  /// routes), plus one PATCH /tag for all the other changed tags.
  /// Returns true when every change was saved; on failure the error was already shown.
  ///
  /// Calls run one after another and stop at the first failure. Whatever was saved before it is kept,
  /// and the form restarts from the saved values (so an unsaved edit of the failing field is dropped).
  Future<bool> save({String? title, Map<String, dynamic>? tags}) async {
    final audio = state.audio;
    if (audio == null || state.isSaving) return false;

    final id = '${audio['_id']}';
    final saved = Map<String, dynamic>.of(audio);
    final savedTags = Map<String, dynamic>.of((audio['tags'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{});

    final artists = (tags?['artists'] as List?)?.cast<String>();
    final album = tags?['album'] as String?;
    final lyrics = tags?['lyrics'] as String?;
    // Everything else goes through the generic /tag route. Artists and album must NOT: their routes also
    // create the artist / album records and update the search index, /tag only rewrites the audio's tags.
    final others = <String, dynamic>{
      for (final e in (tags ?? const <String, dynamic>{}).entries)
        if (e.key != 'artists' && e.key != 'album' && e.key != 'lyrics') e.key: e.value,
    };

    // The title goes first: it is the call most likely to be rejected (TITLE_NOT_UNIQUE),
    // so when it fails nothing has been changed yet.
    final steps = <({Future<ApiCallResult<dynamic>> Function() send, void Function() apply})>[
      if (title != null) (send: () => _api.updateTitle(audioId: id, title: title), apply: () => saved['title'] = title),
      if (others.isNotEmpty) (send: () => _api.updateTags(audioId: id, tags: others), apply: () => savedTags.addAll(others)),
      if (artists != null) (send: () => _api.updateArtists(audioId: id, artists: artists), apply: () => savedTags['artists'] = artists),
      if (album != null) (send: () => _api.updateAlbum(audioId: id, album: album), apply: () => savedTags['album'] = album),
      if (lyrics != null) (send: () => _api.updateLyrics(audioId: id, lyrics: lyrics), apply: () => savedTags['lyrics'] = lyrics),
    ];

    state = state.copyWith(isSaving: true);

    var applied = false;
    var ok = true;
    for (final step in steps) {
      final result = await step.send();
      if (!ref.mounted) return false;

      if (result.isFailure) {
        ok = false;
        break;
      }
      step.apply();
      applied = true;
    }

    state = state.copyWith(
      isSaving: false,
      // anything that was saved becomes the form's new starting point
      revision: applied ? state.revision + 1 : null,
      audio: applied ? {...saved, 'tags': savedTags} : null,
    );
    return ok;
  }
}

/// autoDispose: leaving the page cancels polling.
final audioUploadProvider = NotifierProvider.autoDispose<AudioUploadNotifier, UploadState>(AudioUploadNotifier.new);
