import 'dart:async';
import 'dart:convert';

import 'package:avarim/components/button.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/theme/app_colors.dart';
import 'package:avarim/theme/theme_radius.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/lib/talker.dart';

class TextEditor extends ConsumerStatefulWidget {
  final bool editing;
  final String? json;
  final Future<void> Function(List<Map<String, dynamic>> json)? onSave;

  const TextEditor({super.key, required this.editing, this.json, this.onSave});

  @override
  ConsumerState<TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends ConsumerState<TextEditor> {
  final QuillController _controller = () {
    return QuillController.basic(config: QuillControllerConfig());
  }();
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();

  bool _hasChanged = false;
  bool _saving = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _controller.readOnly = !widget.editing;

    try {
      if (widget.json != null && widget.json != '') {
        final json = jsonDecode(widget.json!);
        _controller.document = Document.fromJson(json);
      }
    } catch (e) {
      _controller.document = Document();
      talker.error('Failure while trying to parse input json for the rich text editor, falling back to empty content for the editor.', e);
    }

    // _controller.addListener(() {
    //   setState(() {
    //     _hasChanged = true;
    //   });
    //   _timer?.cancel();
    //   _timer = Timer(Duration(seconds: 2), () {
    //     _onSave();
    //   });
    // });
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorScrollController.dispose();
    _editorFocusNode.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!widget.editing) return;

    if (_saving) return;

    try {
      setState(() {
        _saving = true;
      });

      final json = _controller.document.toDelta().toJson();

      await widget.onSave?.call(json);
      if (!mounted) return;

      setState(() {
        _hasChanged = false;
        _saving = false;
      });
    } catch (e) {
      talker.error('The _onSave method in TextEditor widget throws an error', e);
      if (!mounted) return;

      setState(() {
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _controller.readOnly = !widget.editing;

    final theme = Theme.of(context);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 7,
        children: [
          if (widget.editing)
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadiusGeometry.circular(AppRadius.md), color: theme.colorScheme.surface),
              child: QuillSimpleToolbar(
                controller: _controller,
                config: QuillSimpleToolbarConfig(
                  toolbarIconCrossAlignment: WrapCrossAlignment.center,
                  toolbarIconAlignment: WrapAlignment.start,
                  buttonOptions: QuillSimpleToolbarButtonOptions(
                    base: QuillToolbarBaseButtonOptions(
                      afterButtonPressed: () {
                        final isDesktop = const {TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS}.contains(defaultTargetPlatform);
                        if (isDesktop) {
                          _editorFocusNode.requestFocus();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),

          Container(
            decoration: BoxDecoration(borderRadius: BorderRadiusGeometry.circular(10), color: theme.colorScheme.surface),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: QuillEditor.basic(
                controller: _controller,
                focusNode: _editorFocusNode,
                scrollController: _editorScrollController,
                config: QuillEditorConfig(
                  placeholder: !widget.editing ? null : l10n.text_editor_placeholder,
                  minHeight: 60,
                  requestKeyboardFocusOnCheckListChanged: true,
                ),
              ),
            ),
          ),

          if (widget.editing)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Button(
                  type: ButtonType.text,
                  color: _hasChanged ? theme.extension<AppColors>()!.warning : theme.colorScheme.primary,
                  icon: Icons.save,
                  isLoading: _saving,
                  onPressed: _onSave,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
