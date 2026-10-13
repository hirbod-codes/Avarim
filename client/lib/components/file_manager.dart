import 'package:avarim/api/models/leaf.dart';
import 'package:avarim/api/providers/files.dart';
import 'package:avarim/api/providers/folders.dart';
import 'package:avarim/components/contents/choose_content_type_dialog.dart';
import 'package:avarim/components/dialogs/upload/audio_upload_dialog.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/components/content_container.dart';
import 'package:avarim/components/dialogs/upload/image_upload_dialog.dart';
import 'package:avarim/components/dialogs/upload/video_upload_dialog.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/theme/app_colors.dart';
import 'package:avarim/theme/theme_radius.dart';
import 'package:avarim/theme/theme_spacing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import 'header_delegate.dart';

class FileManager extends ConsumerStatefulWidget {
  final Leaf file;
  final Function? onClose;

  const FileManager({super.key, required this.file, this.onClose});

  @override
  ConsumerState<FileManager> createState() => _FileManager();
}

class _FileManager extends ConsumerState<FileManager> {
  bool _editing = false;
  int? _isDeleting;
  int? _isAdding;

  int? _movingContentIndex;
  bool _isMovingContent = false;

  Future<void> _onContentAdd() async {
    try {
      setState(() {
        _isAdding = -1;
      });

      ContentType? type = await showDialog<ContentType?>(context: context, builder: (_) => ChooseContentTypeDialog());
      if (type == null || !mounted) return;

      await ref.read(filesProvider.notifier).addContent(Content(type: type, value: []));
    } finally {
      if (mounted) {
        setState(() {
          _isAdding = null;
        });
      }
    }
  }

  Future<void> _onContentValueAdd({required int index}) async {
    setState(() {
      _isAdding = index;
    });
    try {
      final p = ref.watch(filesProvider);
      final file = p.files![p.fileIndex];
      List<Content> contents;
      if (p.isTerm) {
        contents = file.termContents;
      } else {
        contents = file.definitionContents;
      }

      switch (contents[index].type) {
        case ContentType.string:
          await ref.read(filesProvider.notifier).addContentValue('', index);
          break;

        case ContentType.richText:
          await ref.read(filesProvider.notifier).addContentValue('', index);
          break;

        case ContentType.imageId:
          String? newId = await showDialog<String?>(context: context, builder: (_) => ImageUploadDialog());
          if (newId == null || !mounted) return;
          talker.info({newId});

          await ref.read(filesProvider.notifier).addContentValue(newId, index);
          break;
        case ContentType.videoId:
          String? newId = await showDialog<String?>(context: context, builder: (_) => VideoUploadDialog());
          if (newId == null || !mounted) return;
          talker.info({newId});

          await ref.read(filesProvider.notifier).addContentValue(newId, index);
        case ContentType.audioId:
          String? newId = await showDialog<String?>(context: context, builder: (_) => AudioUploadDialog());
          if (newId == null || !mounted) return;
          talker.info({newId});

          await ref.read(filesProvider.notifier).addContentValue(newId, index);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAdding = null;
        });
      }
    }
  }

  Future<bool> _contentDelete(int index) async {
    setState(() {
      _isDeleting = index;
    });

    final result = await ref.read(filesProvider.notifier).removeContent(index);

    if (mounted) {
      setState(() {
        _isDeleting = null;
      });
    }

    return result;
  }

  Future<void> _showContentDeleteDialog(int index) async {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        AppLocalizations l10n = AppLocalizations.of(context)!;

        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.file_manager_content_delete_dialog_heading, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Button(
                        type: ButtonType.text,
                        color: theme.colorScheme.error,
                        onPressed: () {
                          if (mounted) Navigator.pop(context);
                        },
                        label: l10n.no,
                      ),

                      const SizedBox(width: 8),

                      Button(
                        type: ButtonType.elevated,
                        color: theme.extension<AppColors>()!.success,
                        onPressed: () async {
                          final result = await _contentDelete(index);
                          // ignore: use_build_context_synchronously
                          if (mounted && result) Navigator.pop(context);
                        },
                        label: l10n.yes,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final p = ref.watch(filesProvider);
    final file = p.files![p.fileIndex];
    final contents = p.isTerm ? file.termContents : file.definitionContents;

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final spacing = getSpacing(maxWidth);

        return Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: EdgeInsetsGeometry.all(spacing.padding),
            child: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: HeaderDelegate(
                    height: _editing ? 200 : 150,
                    child: Container(
                      decoration: BoxDecoration(color: theme.colorScheme.surface),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Close button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Button(
                                type: ButtonType.text,
                                color: theme.colorScheme.onSurface,
                                icon: Icons.close,
                                onPressed: () {
                                  if (widget.onClose != null) widget.onClose!();
                                },
                              ),
                            ],
                          ),

                          SizedBox(height: spacing.listItemSpacing),

                          // Edit and flip button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Button(
                                type: ButtonType.text,
                                color: theme.colorScheme.primary,
                                icon: Icons.flip,
                                label: l10n.flip,
                                onPressed: () {
                                  flip();
                                },
                              ),
                              Button(
                                type: ButtonType.text,
                                color: theme.colorScheme.primary,
                                icon: _editing ? Icons.remove_red_eye_outlined : Icons.edit_square,
                                onPressed: () {
                                  setState(() {
                                    _editing = !_editing;
                                  });
                                },
                              ),
                            ],
                          ),

                          SizedBox(height: spacing.listItemSpacing),

                          // Title
                          Text(widget.file.title, style: TextStyle(fontSize: 30)),

                          Divider(color: theme.colorScheme.outlineVariant, height: 1),

                          if (_editing) SizedBox(height: spacing.listItemSpacing),

                          if (_editing)
                            Button(
                              isLoading: _isAdding == -1,
                              type: ButtonType.outlined,
                              color: theme.extension<AppColors>()!.success,
                              onPressed: () {
                                _onContentAdd();
                              },
                              label: l10n.add_content,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                SliverList(
                  delegate: SliverChildBuilderDelegate(childCount: contents.length, (context, contentIndex) {
                    Content content = p.isTerm ? file.termContents[contentIndex] : file.definitionContents[contentIndex];

                    IconData contentIcon;
                    switch (content.type) {
                      case ContentType.imageId:
                        contentIcon = Icons.image;
                        break;
                      case ContentType.audioId:
                        contentIcon = Icons.audio_file;
                        break;
                      case ContentType.videoId:
                        contentIcon = Icons.video_collection_rounded;
                        break;
                      case ContentType.richText:
                        contentIcon = Icons.text_fields;
                        break;
                      case ContentType.string:
                        contentIcon = Icons.text_format;
                        break;
                    }

                    return Column(
                      spacing: spacing.listItemSpacing,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_movingContentIndex != null && _movingContentIndex != contentIndex && _movingContentIndex != contentIndex - 1)
                          Button(
                            type: ButtonType.elevated,
                            isLoading: _isMovingContent,
                            onPressed: () async {
                              setState(() {
                                _isMovingContent = true;
                              });

                              await ref.watch(filesProvider.notifier).moveContent(_movingContentIndex!, contentIndex);
                              if (!mounted) return;

                              setState(() {
                                _movingContentIndex = null;
                                _isMovingContent = false;
                              });
                            },
                          ),
                        Container(
                          margin: EdgeInsetsGeometry.fromSTEB(0, 0, 0, spacing.listItemSpacing),
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            border: BoxBorder.all(color: theme.colorScheme.outlineVariant, width: 1),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(spacing.padding),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: spacing.listItemSpacing,
                              children: [
                                Row(
                                  children: [
                                    IconButton(onPressed: () {}, icon: Icon(contentIcon)),
                                    if (_editing)
                                      Button(
                                        type: ButtonType.text,
                                        icon: Icons.drive_file_move_outlined,
                                        iconSize: 24,
                                        onPressed: _movingContentIndex != null
                                            ? null
                                            : () {
                                                setState(() {
                                                  _movingContentIndex = contentIndex;
                                                  _isMovingContent = false;
                                                });
                                              },
                                      ),
                                  ],
                                ),
                                if (_editing)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Button(
                                        type: ButtonType.text,
                                        color: theme.extension<AppColors>()!.success,
                                        icon: Icons.add_circle_outline,
                                        iconSize: 24,
                                        isLoading: _isAdding == contentIndex,
                                        onPressed: () => _onContentValueAdd(index: contentIndex),
                                      ),
                                      Button(
                                        type: ButtonType.text,
                                        color: theme.colorScheme.error,
                                        icon: Icons.highlight_remove,
                                        isLoading: _isDeleting == contentIndex,
                                        iconSize: 24,
                                        onPressed: () => _showContentDeleteDialog(contentIndex),
                                      ),
                                    ],
                                  ),
                                ContentContainer(leafId: file.id, contentIndex: contentIndex, editing: _editing),
                              ],
                            ),
                          ),
                        ),
                        if (contentIndex == contents.length - 1 && _movingContentIndex != null && _movingContentIndex != contentIndex)
                          Button(
                            type: ButtonType.elevated,
                            isLoading: _isMovingContent,
                            onPressed: () async {
                              setState(() {
                                _isMovingContent = true;
                              });

                              await ref.watch(filesProvider.notifier).moveContent(_movingContentIndex!, contentIndex + 1);
                              if (!mounted) return;

                              setState(() {
                                _movingContentIndex = null;
                                _isMovingContent = false;
                              });
                            },
                          ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void flip() {
    ref.read(filesProvider.notifier).flip();
    ref.read(foldersProvider.notifier).flip(isTerm: ref.watch(filesProvider).isTerm);
  }
}
