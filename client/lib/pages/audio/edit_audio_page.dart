// edit_audio_page.dart
//
// Two ways in (decided by the `audioId` query parameter):
//
//   EditAudioPage(audioId: 'abc')  -> edit an existing audio
//       GET  /api/audio/info?audioId=...  => { status: 'success', data: audio }
//
//   EditAudioPage()                -> upload a new audio, then edit it
//       1. AudioUploadDialog      -> POST /api/audio/  (multipart)   => { status: 'queued', data: { id } }
//       2. poll every 5 seconds   -> GET  /api/audio/is_upload_finished
//       3. when finished          -> GET  /api/audio/info?audioId=...
//
// Editing (both ways):
//   - cover art               -> GET / PUT /api/audio/coverArt/:audioId   (see cover_art_section.dart)
//   - title + tags            (everything else is shown read-only)
//        title uniqueness     -> GET  /api/audio/is_title_unique (204 = free, 400 TITLE_NOT_UNIQUE)
//   - "Update"                -> POST /api/audio/  { updates: { audioId, title?, tags? } }
//
// Everything is in one file for easy copy/paste; split it when you customize it.

import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/components/dialogs/upload/audio_upload_dialog.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/pages/audio/cover_art_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

const kAudioPath = '/api/audio/';
const kIsUploadFinishedPath = '/api/audio/is_upload_finished';
const kAudioInfoPath = '/api/audio/info';
const kIsTitleUniquePath = '/api/audio/is_title_unique';

const kPollInterval = Duration(seconds: 5);

/// Gives up waiting after this many polls (120 x 5s = 10 minutes).
const kMaxPollAttempts = 120;

const kTitleCheckDebounce = Duration(milliseconds: 600);

// ─────────────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────────────

bool _isCancel(Object e) => e is DioException && CancelToken.isCancel(e);

String _describeError(Object e) {
  if (e is StateError) return e.message;
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final code = data['error_code'];
      if (code == 'TITLE_NOT_UNIQUE') return 'An audio with this title already exists';
      final message = data['message'] ?? data['error'];
      if (message is String && message.isNotEmpty) return message;
      if (code is String && code.isNotEmpty) return code;
    }
    return e.message ?? 'Request failed';
  }
  return e.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

class AudioUploadApi {
  AudioUploadApi(this._dio);
  final Dio _dio;

  /// Whether the server finished processing the queued upload [audioId].
  /// Throws a [StateError] if the server reports that the job failed.
  Future<bool> isUploadFinished(String audioId, {CancelToken? cancelToken}) async {
    final res = await apiCall(() => _dio.get<dynamic>(kIsUploadFinishedPath, queryParameters: {'audioId': audioId}, cancelToken: cancelToken));

    if (res.isFailure) throw StateError('The server failed to process this upload');

    return res.isSuccess;
  }

  Future<Map<String, dynamic>> getInfo(String audioId, {CancelToken? cancelToken}) async {
    final res = await _dio.get<dynamic>(kAudioInfoPath, queryParameters: {'audioId': audioId}, cancelToken: cancelToken);

    final body = res.data;
    if (body is Map && body['status'] == 'success' && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw StateError('Unexpected response while loading the audio info');
  }

  /// 204 -> free, 400 + TITLE_NOT_UNIQUE -> taken. Anything else throws.
  Future<bool> isTitleUnique(String title, {CancelToken? cancelToken}) async {
    final res = await _dio.get<dynamic>(
      kIsTitleUniquePath,
      queryParameters: {'title': title},
      cancelToken: cancelToken,
      options: Options(validateStatus: (s) => s != null && (s < 300 || s == 400)),
    );

    if (res.statusCode == 400) {
      final data = res.data;
      if (data is Map && data['error_code'] == 'TITLE_NOT_UNIQUE') return false;
      throw StateError('The title check was rejected');
    }
    return true;
  }

  /// Payload: { updates: { audioId, title?, tags? } }
  /// If your backend expects `audioId` NEXT TO `updates` instead, move it here.
  Future<void> update({required String audioId, String? title, Map<String, dynamic>? tags}) async {
    final res = await _dio.post<dynamic>(
      kAudioPath,
      data: {
        'updates': {'audioId': audioId, 'title': ?title, if (tags != null && tags.isNotEmpty) 'tags': tags},
      },
    );

    final body = res.data;
    if (body is Map && body['status'] == 'error') {
      throw StateError(body['message']?.toString() ?? body['error_code']?.toString() ?? 'Update failed');
    }
  }
}

final audioUploadApiProvider = Provider<AudioUploadApi>((ref) => AudioUploadApi(ref.watch(authDioProvider)));

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

enum UploadPhase { idle, processing, loading, failed, editing }

class UploadState {
  const UploadState({this.phase = UploadPhase.idle, this.id, this.audio, this.error, this.isSaving = false, this.revision = 0, this.existing = false});

  final UploadPhase phase;

  /// Id of the audio being uploaded / edited (used for polling / info).
  final String? id;

  /// The audio document returned by `/info` (kept up to date after saves).
  final Map<String, dynamic>? audio;
  final String? error;
  final bool isSaving;

  /// Bumped after each successful save so the form re-initializes from the new values.
  final int revision;

  /// True when an existing audio was opened by id (no upload flow).
  final bool existing;

  UploadState copyWith({
    UploadPhase? phase,
    String? id,
    Map<String, dynamic>? audio,
    String? error,
    bool clearError = false,
    bool? isSaving,
    int? revision,
    bool? existing,
  }) => UploadState(
    phase: phase ?? this.phase,
    id: id ?? this.id,
    audio: audio ?? this.audio,
    error: clearError ? null : (error ?? this.error),
    isSaving: isSaving ?? this.isSaving,
    revision: revision ?? this.revision,
    existing: existing ?? this.existing,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

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

    try {
      final audio = await _api.getInfo(audioId, cancelToken: token);
      if (!ref.mounted || token.isCancelled) return;
      state = state.copyWith(phase: UploadPhase.editing, audio: audio);
    } catch (e, st) {
      if (!ref.mounted || _isCancel(e)) return;
      _fail(e, st);
    }
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
      final finished = await _api.isUploadFinished(id, cancelToken: token);
      if (!ref.mounted || token.isCancelled) return;
      _consecutiveErrors = 0;

      if (finished) {
        _timer?.cancel();
        final audio = await _api.getInfo(id, cancelToken: token);
        if (!ref.mounted || token.isCancelled) return;
        state = state.copyWith(phase: UploadPhase.editing, audio: audio);
      } else if (_attempts >= kMaxPollAttempts) {
        _timer?.cancel();
        _fail(StateError('Timed out waiting for the upload to finish processing'));
      }
    } catch (e, st) {
      if (!ref.mounted || _isCancel(e)) return;
      // A flaky network gets a couple of retries; a server-reported failure is final.
      _consecutiveErrors++;
      if (_consecutiveErrors >= 3 || e is StateError) {
        _timer?.cancel();
        _fail(e, st);
      }
    } finally {
      _checking = false;
    }
  }

  void _fail(Object e, [StackTrace? st]) {
    talker.error('audio upload / load failed', e, st);
    state = state.copyWith(phase: UploadPhase.failed, error: _describeError(e));
  }

  /// Sends only what changed. Returns true on success.
  Future<bool> save({String? title, Map<String, dynamic>? tags}) async {
    final audio = state.audio;
    if (audio == null || state.isSaving) return false;

    state = state.copyWith(isSaving: true);
    try {
      await _api.update(audioId: '${audio['_id']}', title: title, tags: tags);
      if (!ref.mounted) return true;

      final oldTags = (audio['tags'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      state = state.copyWith(
        isSaving: false,
        revision: state.revision + 1,
        audio: {
          ...audio,
          'title': ?title,
          if (tags != null) 'tags': {...oldTags, ...tags},
        },
      );
      return true;
    } catch (e, st) {
      talker.error('audio update failed', e, st);
      if (ref.mounted) state = state.copyWith(isSaving: false);
      NotificationService.showError(message: _describeError(e));
      return false;
    }
  }
}

/// autoDispose: leaving the page cancels polling.
final audioUploadProvider = NotifierProvider.autoDispose<AudioUploadNotifier, UploadState>(AudioUploadNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class EditAudioPage extends ConsumerStatefulWidget {
  const EditAudioPage({super.key, this.audioId});

  /// The `audioId` query parameter. With an id the page edits that audio;
  /// without one it starts the upload flow.
  final String? audioId;

  @override
  ConsumerState<EditAudioPage> createState() => _EditAudioPageState();
}

class _EditAudioPageState extends ConsumerState<EditAudioPage> {
  bool get _hasId => widget.audioId != null && widget.audioId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(EditAudioPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioId != widget.audioId) _open();
  }

  void _open() {
    final id = widget.audioId;
    // After the first build: providers can't be modified while the tree is building.
    Future.microtask(() {
      if (!mounted) return;
      final notifier = ref.read(audioUploadProvider.notifier);
      if (id != null && id.isNotEmpty) {
        unawaited(notifier.openExisting(id));
      } else {
        notifier.reset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(audioUploadProvider);

    final Widget body = switch (s.phase) {
      // With an id, `idle` is only the frame before loading starts.
      UploadPhase.idle => _hasId ? const _LoadingStep() : const _StartStep(),
      UploadPhase.processing => _ProcessingStep(state: s),
      UploadPhase.loading => const _LoadingStep(),
      UploadPhase.failed => _FailedStep(state: s),
      UploadPhase.editing => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverArtSection(key: ValueKey('${s.audio!['_id']}'), audioId: '${s.audio!['_id']}'),
          const SizedBox(height: 24),
          _EditForm(key: ValueKey(s.revision), audio: s.audio!, isSaving: s.isSaving, isExisting: s.existing),
        ],
      ),
    };

    return Scaffold(
      appBar: AppBar(title: Text(_hasId ? 'Edit audio' : 'Upload audio')),
      body: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight > 48 ? c.maxHeight - 48 : 0),
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: body),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Steps: start / processing / loading / failed
// ─────────────────────────────────────────────────────────────────────────────

class _StartStep extends ConsumerWidget {
  const _StartStep();

  Future<void> _openDialog(BuildContext context, WidgetRef ref) async {
    // Not dismissible by tapping outside: that would drop the result of an upload still in flight.
    final result = await showDialog<dynamic>(context: context, barrierDismissible: false, builder: (_) => const AudioUploadDialog());
    if (!context.mounted) return;
    if (result == null) {
      NotificationService.showError(message: 'Id not found');
      return;
    }

    // The dialog pops with the response's `data`, i.e. `{ id }`.
    final id = result is Map ? result['id'] : null;
    if (id is! String || id.isEmpty) {
      NotificationService.showError(message: 'The upload was accepted, but the server did not return a id');
      return;
    }
    ref.read(audioUploadProvider.notifier).startProcessing(id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.upload_file, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Upload an audio file', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'The file is processed on the server. When it is done you can review and edit its title and tags.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: () => _openDialog(context, ref), icon: const Icon(Icons.upload), label: const Text('Upload audio')),
      ],
    );
  }
}

class _ProcessingStep extends ConsumerWidget {
  const _ProcessingStep({required this.state});
  final UploadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text('Processing audio…', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(state.id ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Text('Checking every ${kPollInterval.inSeconds} seconds. Keep this page open.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 24),
        OutlinedButton(onPressed: ref.read(audioUploadProvider.notifier).reset, child: const Text('Cancel')),
      ],
    );
  }
}

class _LoadingStep extends StatelessWidget {
  const _LoadingStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text('Loading audio…', style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _FailedStep extends ConsumerWidget {
  const _FailedStep({required this.state});
  final UploadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(audioUploadProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text('Something went wrong', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(state.error ?? 'Unknown error', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            // A queued job can simply be checked again; an existing audio can be loaded again.
            if (state.id != null) FilledButton(onPressed: notifier.resume, child: Text(state.existing ? 'Try again' : 'Check again')),
            if (!state.existing) OutlinedButton(onPressed: notifier.reset, child: const Text('Start over')),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tag field specs (mirror the backend `audioTags` schema)
// ─────────────────────────────────────────────────────────────────────────────

enum _Kind { text, multiline, integer, decimal, list, flag }

class _TagSpec {
  const _TagSpec(
    this.key,
    this.label,
    this.kind, {
    this.hint,
    this.min,
    this.max,
    this.maxLength = 2000,
    this.pattern,
    this.patternMessage,
    this.maxItems = 50,
    this.normalize,
  });

  final String key;
  final String label;
  final _Kind kind;
  final String? hint;
  final num? min;
  final num? max;

  /// Max length of the text (or of each list item).
  final int maxLength;

  /// Regex source the text (or each list item) must match.
  final String? pattern;
  final String? patternMessage;
  final int maxItems;

  /// Applied to list items before validation (e.g. ISRC upper-casing).
  final String Function(String)? normalize;
}

class _TagGroup {
  const _TagGroup(this.title, this.fields);
  final String title;
  final List<_TagSpec> fields;
}

String _normalizeIsrc(String v) => v.replaceAll('-', '').replaceAll(' ', '').toUpperCase();

const _tagGroups = [
  _TagGroup('Track info', [
    _TagSpec('audioTitle', 'Title in file tags', _Kind.text),
    _TagSpec('artists', 'Artists', _Kind.list),
    _TagSpec('album', 'Album', _Kind.text),
    _TagSpec('genres', 'Genres', _Kind.list),
    _TagSpec('year', 'Year', _Kind.integer, min: 1000, max: 9999),
    _TagSpec(
      'releaseDate',
      'Release date',
      _Kind.text,
      hint: 'YYYY, YYYY-MM or YYYY-MM-DD',
      pattern: r'^\d{4}(-\d{2}(-\d{2})?)?$',
      patternMessage: 'Use YYYY, YYYY-MM or YYYY-MM-DD',
    ),
  ]),
  _TagGroup('Numbering', [
    _TagSpec('trackNumber', 'Track number', _Kind.integer, min: 1),
    _TagSpec('trackTotal', 'Track total', _Kind.integer, min: 1),
    _TagSpec('discNumber', 'Disc number', _Kind.integer, min: 1),
    _TagSpec('discTotal', 'Disc total', _Kind.integer, min: 1),
    _TagSpec('compilation', 'Compilation', _Kind.flag),
  ]),
  _TagGroup('Credits & release', [
    _TagSpec('composers', 'Composers', _Kind.list),
    _TagSpec('lyricists', 'Lyricists', _Kind.list),
    _TagSpec('producers', 'Producers', _Kind.list),
    _TagSpec('label', 'Label', _Kind.text),
    _TagSpec('catalogNumber', 'Catalog number', _Kind.text),
    _TagSpec('copyright', 'Copyright', _Kind.text),
    _TagSpec('language', 'Language', _Kind.text),
  ]),
  _TagGroup('Other', [
    _TagSpec('bpm', 'BPM', _Kind.decimal, min: 0.01, max: 400),
    _TagSpec('key', 'Musical key', _Kind.text),
    _TagSpec(
      'isrc',
      'ISRC',
      _Kind.list,
      maxItems: 10,
      pattern: r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$',
      patternMessage: 'Invalid ISRC (e.g. USRC17607839)',
      normalize: _normalizeIsrc,
    ),
    _TagSpec('comment', 'Comment', _Kind.multiline, maxLength: 20000),
    _TagSpec('lyrics', 'Lyrics', _Kind.multiline, maxLength: 200000),
  ]),
];

final _allSpecs = [for (final g in _tagGroups) ...g.fields];

// ─────────────────────────────────────────────────────────────────────────────
// Edit form
// ─────────────────────────────────────────────────────────────────────────────

enum _TitleStatus { unchanged, checking, available, taken, unknown }

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({super.key, required this.audio, required this.isSaving, required this.isExisting});

  final Map<String, dynamic> audio;
  final bool isSaving;

  /// Opened by id (no upload flow), so there is no "Upload another".
  final bool isExisting;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  final _formKey = GlobalKey<FormState>();

  late final String _baseTitle;
  late final TextEditingController _title;

  // text / multiline / integer / decimal fields
  final _text = <String, TextEditingController>{};
  final _baseText = <String, String>{};
  // list fields
  final _lists = <String, List<String>>{};
  final _baseLists = <String, List<String>>{};
  // flag fields
  final _flags = <String, bool>{};
  final _baseFlags = <String, bool>{};

  Timer? _titleDebounce;
  CancelToken? _titleToken;
  _TitleStatus _titleStatus = _TitleStatus.unchanged;

  @override
  void initState() {
    super.initState();

    _baseTitle = (widget.audio['title'] as String? ?? '').trim();
    _title = TextEditingController(text: _baseTitle)..addListener(_onTitleChanged);

    final tags = (widget.audio['tags'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

    for (final s in _allSpecs) {
      final v = tags[s.key];
      switch (s.kind) {
        case _Kind.text:
        case _Kind.multiline:
        case _Kind.integer:
        case _Kind.decimal:
          final initial = v == null ? '' : (v is num && s.kind == _Kind.integer ? v.toInt().toString() : v.toString());
          _baseText[s.key] = initial.trim();
          _text[s.key] = TextEditingController(text: initial)..addListener(_onChanged);
        case _Kind.list:
          final items = (v as List?)?.map((e) => e.toString()).toList() ?? <String>[];
          _lists[s.key] = [...items];
          _baseLists[s.key] = [...items];
        case _Kind.flag:
          final b = v as bool? ?? false;
          _flags[s.key] = b;
          _baseFlags[s.key] = b;
      }
    }
  }

  @override
  void dispose() {
    _titleDebounce?.cancel();
    _titleToken?.cancel();
    _title.dispose();
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() => setState(() {});

  // ── title uniqueness ───────────────────────────────────────────────────────

  void _onTitleChanged() {
    final t = _title.text.trim();
    _titleDebounce?.cancel();
    _titleToken?.cancel();

    // The audio already owns its current title, so only a CHANGED title needs checking.
    if (t.isEmpty || t == _baseTitle) {
      setState(() => _titleStatus = _TitleStatus.unchanged);
      return;
    }

    setState(() => _titleStatus = _TitleStatus.checking);
    _titleDebounce = Timer(kTitleCheckDebounce, () => _checkTitle(t));
  }

  Future<void> _checkTitle(String t) async {
    final token = _titleToken = CancelToken();
    try {
      final free = await ref.read(audioUploadApiProvider).isTitleUnique(t, cancelToken: token);
      if (!mounted || token.isCancelled || _title.text.trim() != t) return;
      setState(() => _titleStatus = free ? _TitleStatus.available : _TitleStatus.taken);
    } catch (e, st) {
      if (_isCancel(e) || !mounted || _title.text.trim() != t) return;
      talker.error('title uniqueness check failed', e, st);
      setState(() => _titleStatus = _TitleStatus.unknown);
    }
  }

  // ── what changed ───────────────────────────────────────────────────────────

  /// Only fields that differ from the loaded values are returned.
  ({String? title, Map<String, dynamic>? tags}) _collect() {
    final t = _title.text.trim();
    final title = t.isNotEmpty && t != _baseTitle ? t : null;

    final tags = <String, dynamic>{};
    for (final s in _allSpecs) {
      switch (s.kind) {
        case _Kind.text:
        case _Kind.multiline:
          final v = _text[s.key]!.text.trim();
          if (v.isNotEmpty && v != _baseText[s.key]) tags[s.key] = v;
        case _Kind.integer:
          final n = int.tryParse(_text[s.key]!.text.trim());
          if (n != null && n != int.tryParse(_baseText[s.key] ?? '')) tags[s.key] = n;
        case _Kind.decimal:
          final n = double.tryParse(_text[s.key]!.text.trim());
          if (n != null && n != double.tryParse(_baseText[s.key] ?? '')) tags[s.key] = n;
        case _Kind.list:
          if (!listEquals(_lists[s.key], _baseLists[s.key])) tags[s.key] = List<String>.of(_lists[s.key]!);
        case _Kind.flag:
          if (_flags[s.key] != _baseFlags[s.key]) tags[s.key] = _flags[s.key];
      }
    }
    return (title: title, tags: tags.isEmpty ? null : tags);
  }

  // ── validation ─────────────────────────────────────────────────────────────

  String? _validateTitle(String? value) {
    final t = (value ?? '').trim();
    if (t.isEmpty) return 'Title is required';
    if (t.length > 2000) return 'Title is too long (max 2000)';
    return null;
  }

  String? _validateSpec(_TagSpec s, String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      // The update payload can only set values, not clear them.
      return (_baseText[s.key] ?? '').isNotEmpty ? "Can't be cleared once set" : null;
    }

    switch (s.kind) {
      case _Kind.integer:
        final n = int.tryParse(v);
        if (n == null) return 'Enter a whole number';
        return _rangeError(s, n);
      case _Kind.decimal:
        final n = double.tryParse(v);
        if (n == null) return 'Enter a number';
        return _rangeError(s, n);
      default:
        if (v.length > s.maxLength) return 'Too long (max ${s.maxLength})';
        if (s.pattern != null && !RegExp(s.pattern!).hasMatch(v)) return s.patternMessage ?? 'Invalid value';
        return null;
    }
  }

  String? _rangeError(_TagSpec s, num n) {
    if (s.min != null && n < s.min!) return s.max == null ? 'Must be at least ${s.min}' : 'Must be between ${s.min} and ${s.max}';
    if (s.max != null && n > s.max!) return 'Must be between ${s.min ?? 0} and ${s.max}';
    return null;
  }

  // ── save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final changes = _collect();
    if (changes.title == null && changes.tags == null) return;

    // The form is rebuilt after a successful save, so grab the messenger first.
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(audioUploadProvider.notifier).save(title: changes.title, tags: changes.tags);
    if (ok) messenger.showSnackBar(const SnackBar(content: Text('Audio updated')));
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changes = _collect();
    final dirty = changes.title != null || changes.tags != null;
    final canSave = dirty && !widget.isSaving && _titleStatus != _TitleStatus.checking && _titleStatus != _TitleStatus.taken;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review & edit', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _titleField(),
          const SizedBox(height: 24),
          for (final g in _tagGroups) ...[_group(theme, g), const SizedBox(height: 24)],
          _ReadOnlyDetails(audio: widget.audio),
          const SizedBox(height: 24),
          Row(
            children: [
              FilledButton.icon(
                onPressed: canSave ? _save : null,
                icon: widget.isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: const Text('Update'),
              ),
              if (!widget.isExisting) ...[
                const SizedBox(width: 12),
                TextButton(onPressed: widget.isSaving ? null : ref.read(audioUploadProvider.notifier).reset, child: const Text('Upload another')),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _titleField() {
    return TextFormField(
      controller: _title,
      validator: _validateTitle,
      decoration: InputDecoration(
        labelText: 'Title',
        border: const OutlineInputBorder(),
        errorText: _titleStatus == _TitleStatus.taken ? 'This title is already taken' : null,
        helperText: switch (_titleStatus) {
          _TitleStatus.checking => 'Checking availability…',
          _TitleStatus.available => 'Title is available',
          _TitleStatus.unknown => "Couldn't verify that this title is available",
          _ => null,
        },
        suffixIcon: switch (_titleStatus) {
          _TitleStatus.checking => const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          _TitleStatus.available => const Icon(Icons.check_circle_outline),
          _ => null,
        },
      ),
    );
  }

  Widget _group(ThemeData theme, _TagGroup g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(g.title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final half = c.maxWidth >= 600 ? (c.maxWidth - 16) / 2 : c.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [for (final s in g.fields) SizedBox(width: (s.kind == _Kind.list || s.kind == _Kind.multiline) ? c.maxWidth : half, child: _field(s))],
            );
          },
        ),
      ],
    );
  }

  Widget _field(_TagSpec s) {
    switch (s.kind) {
      case _Kind.list:
        return _ChipListField(
          label: s.label,
          values: _lists[s.key]!,
          maxItems: s.maxItems,
          maxItemLength: s.maxLength,
          itemPattern: s.pattern,
          itemPatternMessage: s.patternMessage,
          normalize: s.normalize,
          onChanged: (v) => setState(() => _lists[s.key] = v),
        );
      case _Kind.flag:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.label),
          value: _flags[s.key]!,
          onChanged: (v) => setState(() => _flags[s.key] = v),
        );
      case _Kind.text:
      case _Kind.multiline:
      case _Kind.integer:
      case _Kind.decimal:
        final multiline = s.kind == _Kind.multiline;
        return TextFormField(
          controller: _text[s.key],
          validator: (v) => _validateSpec(s, v),
          minLines: multiline ? 3 : null,
          maxLines: multiline ? 8 : 1,
          keyboardType: switch (s.kind) {
            _Kind.integer => TextInputType.number,
            _Kind.decimal => const TextInputType.numberWithOptions(decimal: true),
            _Kind.multiline => TextInputType.multiline,
            _ => TextInputType.text,
          },
          inputFormatters: switch (s.kind) {
            _Kind.integer => [FilteringTextInputFormatter.digitsOnly],
            _Kind.decimal => [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            _ => null,
          },
          decoration: InputDecoration(labelText: s.label, helperText: s.hint, border: const OutlineInputBorder(), alignLabelWithHint: multiline),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chip list field (artists, genres, ...)
// ─────────────────────────────────────────────────────────────────────────────

class _ChipListField extends StatefulWidget {
  const _ChipListField({
    required this.label,
    required this.values,
    required this.onChanged,
    required this.maxItems,
    required this.maxItemLength,
    this.itemPattern,
    this.itemPatternMessage,
    this.normalize,
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final int maxItems;
  final int maxItemLength;
  final String? itemPattern;
  final String? itemPatternMessage;
  final String Function(String)? normalize;

  @override
  State<_ChipListField> createState() => _ChipListFieldState();
}

class _ChipListFieldState extends State<_ChipListField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Text typed but not confirmed with Enter is added when the field loses focus.
    _focus.addListener(() {
      if (!_focus.hasFocus && mounted) _add();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    var v = _controller.text.trim();
    if (v.isEmpty) {
      if (_error != null) setState(() => _error = null);
      return;
    }
    if (widget.normalize != null) v = widget.normalize!(v);

    String? error;
    if (v.length > widget.maxItemLength) {
      error = 'Too long (max ${widget.maxItemLength})';
    } else if (widget.itemPattern != null && !RegExp(widget.itemPattern!).hasMatch(v)) {
      error = widget.itemPatternMessage ?? 'Invalid value';
    } else if (widget.values.length >= widget.maxItems) {
      error = 'At most ${widget.maxItems} items';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    if (!widget.values.contains(v)) widget.onChanged([...widget.values, v]);
    _controller.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            _add();
            _focus.requestFocus();
          },
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: 'Press Enter to add',
            errorText: _error,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(tooltip: 'Add', icon: const Icon(Icons.add), onPressed: _add),
          ),
        ),
        if (widget.values.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (i, v) in widget.values.indexed) InputChip(label: Text(v), onDeleted: () => widget.onChanged([...widget.values]..removeAt(i))),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Read-only details (everything that isn't editable)
// ─────────────────────────────────────────────────────────────────────────────

class _ReadOnlyDetails extends StatelessWidget {
  const _ReadOnlyDetails({required this.audio});

  final Map<String, dynamic> audio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final general = <MapEntry<String, String>>[];
    final technical = <MapEntry<String, String>>[];

    audio.forEach((key, value) {
      if (key == 'title' || key == 'tags' || key.startsWith('__')) return;

      if (key == 'technical' && value is Map) {
        value.forEach((tk, tv) {
          if (tk == 'waveform') return; // long list of numbers, not useful as text
          technical.add(MapEntry(_humanizeKey('$tk'), _formatValue('$tk', tv)));
        });
        return;
      }
      general.add(MapEntry(_humanizeKey(key), _formatValue(key, value)));
    });

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('File details (read-only)', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [for (final e in general) _ReadOnlyRow(label: e.key, value: e.value)],
            ),
          ),
          if (technical.isNotEmpty)
            ExpansionTile(
              title: const Text('Technical details'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [for (final e in technical) _ReadOnlyRow(label: e.key, value: e.value)],
            ),
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

String _humanizeKey(String key) {
  if (key == '_id') return 'ID';
  final spaced = key.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}').replaceAll('_', ' ').trim();
  if (spaced.isEmpty) return key;
  final lower = spaced.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return i == 0 ? '$bytes B' : '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[i]}';
}

String _formatValue(String key, Object? v) {
  if (v == null) return '—';

  if (v is num) {
    // Timestamps are assumed to be epoch milliseconds.
    if (key == 'createdAt' || key == 'updatedAt') {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt()).toLocal().toString().split('.').first;
    }
    if (key == 'sizeBytes' || key == 'totalFilesBytes') return _formatBytes(v.toInt());
    if (key == 'durationSec') {
      final s = v.round();
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    if (key == 'sampleRate') return '${v.round()} Hz';
    return v.toString();
  }

  if (v is bool) return v ? 'Yes' : 'No';
  if (v is List) return v.isEmpty ? '—' : v.map((e) => _formatValue('', e)).join(', ');
  if (v is Map) {
    if (v.isEmpty) return '—';
    return v.entries.map((e) => '${_humanizeKey('${e.key}')}: ${_formatValue('${e.key}', e.value)}').join(' · ');
  }

  final s = v.toString();
  return s.isEmpty ? '—' : s;
}
