// batch_upload_notifier.dart
//
// Uploads many audios ONE AT A TIME:
//
//   for each file:  POST /api/audio/  ->  poll GET /api/audio/is_upload_finished  ->  success?  next file
//
// The next file is only sent once the previous one is finished processing. The first failure
// (upload rejected, processing failed, or timed out) stops the batch: the rest is marked `skipped`
// and the page shows the last audio that DID succeed and the one that failed.
//
// Files already uploaded stay on the server whatever happens afterwards.

import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/pages/edit_audio/batch_upload/picked_audio.dart';
import 'package:avarim/pages/edit_audio/edit_audio_api.dart';
import 'package:avarim/pages/edit_audio/edit_audio_notifier.dart' show kPollInterval, kMaxPollAttempts;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Polling errors tolerated in a row before the file is reported as failed (same as the single upload).
const kMaxConsecutivePollErrors = 3;

enum BatchPhase { idle, running, failed, cancelled, done }

enum BatchItemStatus {
  pending,
  uploading,
  processing,
  done,
  failed,

  /// In flight when the user cancelled.
  cancelled,

  /// Never started because an earlier file failed / the batch was cancelled.
  skipped,
}

class BatchItem {
  const BatchItem(this.audio, {this.status = BatchItemStatus.pending, this.id, this.error, this.progress = 0});

  final PickedAudio audio;
  final BatchItemStatus status;

  /// Server id once the upload was accepted (queued).
  final String? id;
  final String? error;

  /// Upload progress, 0..1.
  final double progress;

  BatchItem copyWith({BatchItemStatus? status, String? id, String? error, bool clearError = false, double? progress}) =>
      BatchItem(audio, status: status ?? this.status, id: id ?? this.id, error: clearError ? null : (error ?? this.error), progress: progress ?? this.progress);
}

class BatchUploadState {
  const BatchUploadState({this.phase = BatchPhase.idle, this.items = const []});

  final BatchPhase phase;
  final List<BatchItem> items;

  bool get isActive => phase != BatchPhase.idle;

  int get doneCount => items.where((i) => i.status == BatchItemStatus.done).length;

  /// The most recent audio that was uploaded AND processed successfully.
  BatchItem? get lastSucceeded => items.where((i) => i.status == BatchItemStatus.done).lastOrNull;

  BatchItem? get failedItem => items.where((i) => i.status == BatchItemStatus.failed).firstOrNull;

  BatchUploadState copyWith({BatchPhase? phase, List<BatchItem>? items}) => BatchUploadState(phase: phase ?? this.phase, items: items ?? this.items);
}

class BatchUploadNotifier extends Notifier<BatchUploadState> {
  CancelToken? _token;

  /// Bumped by every start / stop so an older loop that is still awaiting notices it was replaced.
  int _run = 0;

  AudioUploadApi get _api => ref.read(audioUploadApiProvider);

  @override
  BatchUploadState build() {
    ref.onDispose(_stop);
    return const BatchUploadState();
  }

  void _stop() {
    _run++;
    _token?.cancel();
    _token = null;
  }

  bool _stale(int run) => run != _run || !ref.mounted;

  /// Back to nothing (files already uploaded stay on the server).
  void reset() {
    _stop();
    state = const BatchUploadState();
  }

  /// Starts uploading [files] in order.
  Future<void> start(List<PickedAudio> files) {
    if (files.isEmpty) return Future.value();
    state = BatchUploadState(items: [for (final f in files) BatchItem(f)]);
    return _runFrom(0);
  }

  /// Stops after cancelling the request in flight. A file already accepted by the server
  /// keeps processing there.
  void cancel() {
    if (state.phase != BatchPhase.running) return;
    _stop();
    state = BatchUploadState(
      phase: BatchPhase.cancelled,
      items: [
        for (final it in state.items)
          switch (it.status) {
            BatchItemStatus.uploading || BatchItemStatus.processing => it.copyWith(status: BatchItemStatus.cancelled),
            BatchItemStatus.pending => it.copyWith(status: BatchItemStatus.skipped),
            _ => it,
          },
      ],
    );
  }

  /// Continues from the file that failed / was cancelled. If that file was already accepted by the
  /// server (it has an id) it is checked again instead of being uploaded a second time.
  void retry() {
    if (state.phase != BatchPhase.failed && state.phase != BatchPhase.cancelled) return;

    final start = state.items.indexWhere((i) => i.status != BatchItemStatus.done);
    if (start < 0) return;

    state = state.copyWith(
      items: [
        for (final (n, it) in state.items.indexed)
          if (n < start) it else it.copyWith(status: BatchItemStatus.pending, clearError: true, progress: 0),
      ],
    );
    unawaited(_runFrom(start));
  }

  // ── the loop ───────────────────────────────────────────────────────────────

  Future<void> _runFrom(int start) async {
    _stop();
    final run = _run;
    state = state.copyWith(phase: BatchPhase.running);

    for (var i = start; i < state.items.length; i++) {
      final error = await _process(i, run);
      if (_stale(run)) return; // cancelled, reset or page closed
      if (error != null) {
        _failAt(i, error);
        return;
      }
    }
    state = state.copyWith(phase: BatchPhase.done);
  }

  /// Uploads file [i] and waits until it is processed. Returns null on success, the error message on failure
  /// (or null when the run went stale: the caller checks that itself).
  Future<String?> _process(int i, int run) async {
    final item = state.items[i];
    if (item.status == BatchItemStatus.done) return null;

    final token = _token = CancelToken();

    final existingId = item.id;
    final String id;

    if (existingId == null) {
      _update(i, status: BatchItemStatus.uploading, progress: 0);

      var lastPercent = -1;
      final upload = await _api.uploadAudio(
        item.audio,
        cancelToken: token,
        onProgress: (sent, total) {
          if (total <= 0 || _stale(run)) return;
          final percent = sent * 100 ~/ total;
          if (percent == lastPercent) return; // don't rebuild the page for every chunk
          lastPercent = percent;
          _update(i, progress: sent / total);
        },
      );
      if (_stale(run)) return null;

      if (upload case ApiCallFailure(:final message)) return message;

      final value = upload.dataOrNull?['id'];
      if (value is! String || value.isEmpty) return 'The upload was accepted, but the server did not return an id.';

      id = value;
      _update(i, status: BatchItemStatus.processing, id: id, progress: 1);
    } else {
      id = existingId;
      _update(i, status: BatchItemStatus.processing);
    }

    return _waitUntilProcessed(i, id, token, run);
  }

  /// Polls until `isUploadFinished` succeeds. This is what gates the next upload.
  Future<String?> _waitUntilProcessed(int i, String id, CancelToken token, int run) async {
    var errors = 0;

    for (var attempt = 1; attempt <= kMaxPollAttempts; attempt++) {
      final result = await _api.isUploadFinished(id, cancelToken: token);
      if (_stale(run)) return null;

      if (result case ApiCallFailure(:final message)) {
        // A flaky network gets a couple of retries before the file is reported as failed.
        if (++errors >= kMaxConsecutivePollErrors) return message;
      } else {
        errors = 0;
        if (result.isSuccess) {
          _update(i, status: BatchItemStatus.done);
          return null;
        }
        // queued: still processing
      }

      await Future<void>.delayed(kPollInterval);
      if (_stale(run)) return null;
    }

    return 'Timed out waiting for the upload to finish processing';
  }

  // ── state helpers ──────────────────────────────────────────────────────────

  void _update(int i, {BatchItemStatus? status, String? id, double? progress}) {
    if (!ref.mounted) return;
    final items = [...state.items];
    items[i] = items[i].copyWith(status: status, id: id, progress: progress);
    state = state.copyWith(items: items);
  }

  /// Marks file [i] failed and everything after it skipped.
  void _failAt(int i, String message) {
    if (!ref.mounted) return;
    state = BatchUploadState(
      phase: BatchPhase.failed,
      items: [
        for (final (n, it) in state.items.indexed)
          if (n == i) it.copyWith(status: BatchItemStatus.failed, error: message) else if (n > i) it.copyWith(status: BatchItemStatus.skipped) else it,
      ],
    );
  }
}

/// autoDispose: leaving the page cancels the batch.
final batchUploadProvider = NotifierProvider.autoDispose<BatchUploadNotifier, BatchUploadState>(BatchUploadNotifier.new);
