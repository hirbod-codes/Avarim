// edit_audio_form.dart
//
// The form of EditAudioPage: title (with uniqueness check), tags, read-only details
// and the Update button. Only fields that changed are sent (see edit_audio_notifier.dart: title, artists,
// album and lyrics have their own PATCH routes, every other editable tag goes through PATCH /tag).
// Tags without an editor (audioTitle, albumArtists, ...) are shown read-only.

import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/pages/edit_audio/audio_tag_specs.dart';
import 'package:avarim/pages/edit_audio/chip_list_field.dart';
import 'package:avarim/pages/edit_audio/edit_audio_api.dart';
import 'package:avarim/pages/edit_audio/edit_audio_notifier.dart';
import 'package:avarim/pages/common/read_only_details.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kTitleCheckDebounce = Duration(milliseconds: 600);

enum _TitleStatus { unchanged, checking, available, taken, unknown }

class EditAudioForm extends ConsumerStatefulWidget {
  const EditAudioForm({super.key, required this.audio, required this.isSaving, required this.isExisting});

  final Map<String, dynamic> audio;
  final bool isSaving;

  /// Opened by id (no upload flow), so there is no "Upload another".
  final bool isExisting;

  @override
  ConsumerState<EditAudioForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<EditAudioForm> {
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

    for (final s in kAllTagSpecs) {
      final v = tags[s.key];
      switch (s.kind) {
        case TagKind.text:
        case TagKind.multiline:
        case TagKind.integer:
        case TagKind.decimal:
          final initial = v == null ? '' : (v is num && s.kind == TagKind.integer ? v.toInt().toString() : v.toString());
          _baseText[s.key] = initial.trim();
          _text[s.key] = TextEditingController(text: initial)..addListener(_onChanged);
        case TagKind.list:
          final items = (v as List?)?.map((e) => e.toString()).toList() ?? <String>[];
          _lists[s.key] = [...items];
          _baseLists[s.key] = [...items];
        case TagKind.flag:
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

    final result = await ref.read(audioUploadApiProvider).isTitleUnique(t, cancelToken: token);
    if (!mounted || token.isCancelled || _title.text.trim() != t) return;

    setState(() {
      _titleStatus = switch (result) {
        // 400 TITLE_NOT_UNIQUE: somebody else already uses this title.
        ApiCallFailure(errorCode: kTitleNotUniqueCode) => _TitleStatus.taken,
        // Any other failure: we couldn't verify (this request is silent, so no toast).
        ApiCallFailure() => _TitleStatus.unknown,
        // 204: free.
        _ => _TitleStatus.available,
      };
    });
  }

  // ── what changed ───────────────────────────────────────────────────────────

  /// Only fields that differ from the loaded values are returned.
  ///
  /// A tag the user EMPTIED is returned as `null`: that is the "clear this tag" signal (JSON has no `undefined`),
  /// and the backend unsets it. A tag that was empty and still is, is not returned at all.
  /// The title is required, so it is never cleared.
  ({String? title, Map<String, dynamic>? tags}) _collect() {
    final t = _title.text.trim();
    final title = t.isNotEmpty && t != _baseTitle ? t : null;

    final tags = <String, dynamic>{};
    for (final s in kAllTagSpecs) {
      final hadValue = s.kind == TagKind.list ? (_baseLists[s.key] ?? const []).isNotEmpty : (_baseText[s.key] ?? '').isNotEmpty;

      switch (s.kind) {
        case TagKind.text:
        case TagKind.multiline:
          final v = _text[s.key]!.text.trim();
          if (v.isEmpty) {
            if (hadValue) tags[s.key] = null;
          } else if (v != _baseText[s.key]) {
            tags[s.key] = v;
          }
        case TagKind.integer:
          final raw = _text[s.key]!.text.trim();
          final n = int.tryParse(raw);
          if (raw.isEmpty) {
            if (hadValue) tags[s.key] = null;
          } else if (n != null && n != int.tryParse(_baseText[s.key] ?? '')) {
            tags[s.key] = n;
          }
        case TagKind.decimal:
          final raw = _text[s.key]!.text.trim();
          final n = double.tryParse(raw);
          if (raw.isEmpty) {
            if (hadValue) tags[s.key] = null;
          } else if (n != null && n != double.tryParse(_baseText[s.key] ?? '')) {
            tags[s.key] = n;
          }
        case TagKind.list:
          final items = _lists[s.key]!;
          if (items.isEmpty) {
            if (hadValue) tags[s.key] = null;
          } else if (!listEquals(items, _baseLists[s.key])) {
            tags[s.key] = List<String>.of(items);
          }
        case TagKind.flag:
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

  String? _validateSpec(TagSpec s, String? value) {
    final v = (value ?? '').trim();
    // Every tag is optional: emptying one is allowed and clears it (sent as null, see _collect).
    if (v.isEmpty) return null;

    switch (s.kind) {
      case TagKind.integer:
        final n = int.tryParse(v);
        if (n == null) return 'Enter a whole number';
        return _rangeError(s, n);
      case TagKind.decimal:
        final n = double.tryParse(v);
        if (n == null) return 'Enter a number';
        return _rangeError(s, n);
      default:
        if (v.length > s.maxLength) return 'Too long (max ${s.maxLength})';
        if (s.pattern != null && !RegExp(s.pattern!).hasMatch(v)) return s.patternMessage ?? 'Invalid value';
        return null;
    }
  }

  String? _rangeError(TagSpec s, num n) {
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

  /// The audio with its `tags` reduced to the ones that have no editor above (shown read-only).
  Map<String, dynamic> _readOnlyData() {
    final editable = {for (final s in kAllTagSpecs) s.key};
    final tags = (widget.audio['tags'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return {
      ...widget.audio,
      'tags': {
        for (final e in tags.entries)
          if (!editable.contains(e.key)) e.key: e.value,
      },
    };
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
          for (final g in kTagGroups) ...[_group(theme, g), const SizedBox(height: 24)],
          ReadOnlyDetails(
            data: _readOnlyData(),
            hiddenKeys: const {'title'},
            title: 'File details (read-only)',
            // tags without an editor above get their own section
            nestedSections: const {'tags': 'Other tags', 'technical': 'Technical details'},
          ),
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

  Widget _group(ThemeData theme, TagGroup g) {
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
              children: [
                for (final s in g.fields) SizedBox(width: (s.kind == TagKind.list || s.kind == TagKind.multiline) ? c.maxWidth : half, child: _field(s)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _field(TagSpec s) {
    switch (s.kind) {
      case TagKind.list:
        return ChipListField(
          label: s.label,
          values: _lists[s.key]!,
          maxItems: s.maxItems,
          maxItemLength: s.maxLength,
          itemPattern: s.pattern,
          itemPatternMessage: s.patternMessage,
          normalize: s.normalize,
          onChanged: (v) => setState(() => _lists[s.key] = v),
        );
      case TagKind.flag:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.label),
          value: _flags[s.key]!,
          onChanged: (v) => setState(() => _flags[s.key] = v),
        );
      case TagKind.text:
      case TagKind.multiline:
      case TagKind.integer:
      case TagKind.decimal:
        final multiline = s.kind == TagKind.multiline;
        return TextFormField(
          controller: _text[s.key],
          validator: (v) => _validateSpec(s, v),
          minLines: multiline ? 3 : null,
          maxLines: multiline ? 8 : 1,
          keyboardType: switch (s.kind) {
            TagKind.integer => TextInputType.number,
            TagKind.decimal => const TextInputType.numberWithOptions(decimal: true),
            TagKind.multiline => TextInputType.multiline,
            _ => TextInputType.text,
          },
          inputFormatters: switch (s.kind) {
            TagKind.integer => [FilteringTextInputFormatter.digitsOnly],
            TagKind.decimal => [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            _ => null,
          },
          decoration: InputDecoration(labelText: s.label, helperText: s.hint, border: const OutlineInputBorder(), alignLabelWithHint: multiline),
        );
    }
  }
}