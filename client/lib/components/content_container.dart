import 'dart:convert';

import 'package:avarim/api/providers/files.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/api/models/leaf.dart';
import 'package:avarim/components/contents/audio_container.dart';
import 'package:avarim/components/contents/image_container.dart';
import 'package:avarim/components/contents/text/text_editor.dart';
import 'package:avarim/components/contents/video_container.dart';
import 'package:avarim/theme/theme_radius.dart';
import 'package:avarim/components/contents/tts_button.dart';

class ContentContainer extends ConsumerStatefulWidget {
  final bool editing;
  final int contentIndex;
  final String leafId;

  const ContentContainer({super.key, required this.leafId, required this.contentIndex, required this.editing});

  @override
  ConsumerState<ContentContainer> createState() => _ContentState();
}

class _ContentState extends ConsumerState<ContentContainer> {
  final List<int> _isRemoving = [];
  final List<int> _isUpdatingString = [];

  late List<TextEditingController> stringControllers = [];

  int? _movingContentValueIndex;
  bool _isMovingContentValue = false;

  @override
  void initState() {
    super.initState();

    final p = ref.watch(filesProvider);
    if (p.files == null || p.files!.isEmpty) return;

    final file = p.files![p.fileIndex];
    final contents = p.isTerm ? file.termContents : file.definitionContents;

    if (contents[widget.contentIndex].type == ContentType.string) {
      stringControllers = contents[widget.contentIndex].value.map((v) => TextEditingController(text: v)).toList();
    }
  }

  @override
  void dispose() {
    for (final controller in stringControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final p = ref.watch(filesProvider);
    if (p.files == null || p.files!.isEmpty) return SizedBox.shrink();

    final file = p.files![p.fileIndex];
    final contents = p.isTerm ? file.termContents : file.definitionContents;
    final content = contents[widget.contentIndex];

    AppLocalizations l10n = AppLocalizations.of(context)!;

    Widget removeIcon(String value, int index) {
      return _isRemoving.contains(index)
          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.error))
          : IconButton(
              icon: Icon(Icons.remove),
              onPressed: () async {
                if (_isRemoving.contains(index)) return;

                setState(() {
                  _isRemoving.add(index);
                });

                await ref.read(filesProvider.notifier).removeContentValue(widget.contentIndex, index);
                if (!mounted) return;

                setState(() {
                  _isRemoving.remove(index);
                });
              },
              color: theme.colorScheme.error,
              padding: EdgeInsetsGeometry.all(3),
              constraints: BoxConstraints(minWidth: 10, minHeight: 10),
              iconSize: 18,
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  side: BorderSide(color: theme.colorScheme.error),
                ),
              ),
            );
    }

    switch (content.type) {
      case ContentType.richText:
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: content.value.asMap().entries.map((e) {
            final contentValueIndex = e.key;
            final v = e.value;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_movingContentValueIndex != null && _movingContentValueIndex != contentValueIndex && _movingContentValueIndex != contentValueIndex - 1)
                  Button(
                    type: ButtonType.elevated,
                    isLoading: _isMovingContentValue,
                    onPressed: () async {
                      setState(() {
                        _isMovingContentValue = true;
                      });

                      await ref.watch(filesProvider.notifier).moveContentValue(widget.contentIndex, _movingContentValueIndex!, contentValueIndex);
                      if (!mounted) return;

                      setState(() {
                        _movingContentValueIndex = null;
                        _isMovingContentValue = false;
                      });
                    },
                  ),

                Stack(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: Card(
                        child: TextEditor(
                          key: Key(v),
                          editing: widget.editing,
                          json: v,
                          onSave: (json) async {
                            await ref.read(filesProvider.notifier).setContentValue(jsonEncode(json), widget.contentIndex, contentValueIndex);
                          },
                        ),
                      ),
                    ),
                    if (widget.editing)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Row(
                          children: [
                            Button(
                              type: ButtonType.text,
                              icon: Icons.drive_file_move_outlined,
                              iconSize: 24,
                              onPressed: _movingContentValueIndex != null
                                  ? null
                                  : () {
                                      setState(() {
                                        _movingContentValueIndex = contentValueIndex;
                                        _isMovingContentValue = false;
                                      });
                                    },
                            ),
                            removeIcon(v, contentValueIndex),
                          ],
                        ),
                      ),
                  ],
                ),

                if (contentValueIndex == content.value.length - 1 && _movingContentValueIndex != null && _movingContentValueIndex != contentValueIndex)
                  Button(
                    type: ButtonType.elevated,
                    isLoading: _isMovingContentValue,
                    onPressed: () async {
                      setState(() {
                        _isMovingContentValue = true;
                      });

                      await ref.watch(filesProvider.notifier).moveContentValue(widget.contentIndex, _movingContentValueIndex!, contentValueIndex + 1);
                      if (!mounted) return;

                      setState(() {
                        _movingContentValueIndex = null;
                        _isMovingContentValue = false;
                      });
                    },
                  ),
              ],
            );
          }).toList(),
        );

      case ContentType.string:
        stringControllers = content.value.map((v) => TextEditingController(text: v)).toList();

        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 5,
          children: content.value.asMap().entries.map((e) {
            final contentValueIndex = e.key;
            final v = e.value;

            if (widget.editing) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_movingContentValueIndex != null && _movingContentValueIndex != contentValueIndex && _movingContentValueIndex != contentValueIndex - 1)
                    Button(
                      type: ButtonType.elevated,
                      isLoading: _isMovingContentValue,
                      onPressed: () async {
                        setState(() {
                          _isMovingContentValue = true;
                        });

                        await ref.watch(filesProvider.notifier).moveContentValue(widget.contentIndex, _movingContentValueIndex!, contentValueIndex);
                        if (!mounted) return;

                        setState(() {
                          _movingContentValueIndex = null;
                          _isMovingContentValue = false;
                        });
                      },
                    ),
                  Stack(
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextField(
                            controller: stringControllers[contentValueIndex],
                            decoration: InputDecoration(labelText: l10n.title),
                          ),
                        ),
                      ),

                      Positioned(
                        top: 8,
                        right: 8,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          spacing: 5,
                          children: [
                            Button(
                              type: ButtonType.text,
                              icon: Icons.drive_file_move_outlined,
                              iconSize: 24,
                              onPressed: _movingContentValueIndex != null
                                  ? null
                                  : () {
                                      setState(() {
                                        _movingContentValueIndex = contentValueIndex;
                                        _isMovingContentValue = false;
                                      });
                                    },
                            ),
                            if (_isUpdatingString.contains(contentValueIndex))
                              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.extension<AppColors>()!.success)),
                            if (!_isUpdatingString.contains(contentValueIndex))
                              IconButton(
                                icon: Icon(Icons.done),
                                onPressed: () async {
                                  if (_isUpdatingString.contains(contentValueIndex)) return;

                                  setState(() {
                                    _isUpdatingString.add(contentValueIndex);
                                  });

                                  await ref
                                      .read(filesProvider.notifier)
                                      .setContentValue(stringControllers[contentValueIndex].text.trim(), widget.contentIndex, contentValueIndex);
                                  if (!mounted) return;

                                  setState(() {
                                    _isUpdatingString.remove(contentValueIndex);
                                  });
                                },
                                color: theme.extension<AppColors>()!.success,
                                padding: EdgeInsetsGeometry.all(2.5),
                                constraints: BoxConstraints(minWidth: 10, minHeight: 10),
                                iconSize: 18,
                                style: IconButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    side: BorderSide(color: theme.extension<AppColors>()!.success),
                                  ),
                                ),
                              ),
                            removeIcon(v, contentValueIndex),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (contentValueIndex == content.value.length - 1 && _movingContentValueIndex != null && _movingContentValueIndex != contentValueIndex)
                    Button(
                      type: ButtonType.elevated,
                      isLoading: _isMovingContentValue,
                      onPressed: () async {
                        setState(() {
                          _isMovingContentValue = true;
                        });

                        await ref.watch(filesProvider.notifier).moveContentValue(widget.contentIndex, _movingContentValueIndex!, contentValueIndex + 1);
                        if (!mounted) return;

                        setState(() {
                          _movingContentValueIndex = null;
                          _isMovingContentValue = false;
                        });
                      },
                    ),
                ],
              );
            } else {
              return SizedBox(
                width: double.infinity,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (v != '') TTSButton(word: v),
                        Text(v),
                      ],
                    ),
                  ),
                ),
              );
            }
          }).toList(),
        );

      case ContentType.imageId:
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 10,
            children: content.value.asMap().entries.map((e) {
              final contentValueIndex = e.key;
              final v = e.value;

              return Row(
                spacing: 10,
                children: [
                  if (_movingContentValueIndex != null && _movingContentValueIndex != contentValueIndex && _movingContentValueIndex != contentValueIndex - 1)
                    Button(
                      height: 500,
                      type: ButtonType.elevated,
                      isLoading: _isMovingContentValue,
                      onPressed: () async {
                        setState(() {
                          _isMovingContentValue = true;
                        });

                        await ref.watch(filesProvider.notifier).moveContentValue(widget.contentIndex, _movingContentValueIndex!, contentValueIndex);
                        if (!mounted) return;

                        setState(() {
                          _movingContentValueIndex = null;
                          _isMovingContentValue = false;
                        });
                      },
                    ),
                  SizedBox(
                    height: 500,
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: Stack(
                        children: [
                          ImageContainer(key: Key(v), imageId: v),
                          if (widget.editing)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Row(
                                children: [
                                  Button(
                                    type: ButtonType.text,
                                    icon: Icons.drive_file_move_outlined,
                                    iconSize: 24,
                                    onPressed: _movingContentValueIndex != null
                                        ? null
                                        : () {
                                            setState(() {
                                              _movingContentValueIndex = contentValueIndex;
                                              _isMovingContentValue = false;
                                            });
                                          },
                                  ),
                                  removeIcon(v, contentValueIndex),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (contentValueIndex == content.value.length - 1 && _movingContentValueIndex != null && _movingContentValueIndex != contentValueIndex)
                    Button(
                      height: 500,
                      type: ButtonType.elevated,
                      isLoading: _isMovingContentValue,
                      onPressed: () async {
                        setState(() {
                          _isMovingContentValue = true;
                        });

                        await ref.watch(filesProvider.notifier).moveContentValue(widget.contentIndex, _movingContentValueIndex!, contentValueIndex + 1);
                        if (!mounted) return;

                        setState(() {
                          _movingContentValueIndex = null;
                          _isMovingContentValue = false;
                        });
                      },
                    ),
                ],
              );
            }).toList(),
          ),
        );

      case ContentType.videoId:
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 10,
            children: content.value.asMap().entries.map((e) {
              final contentValueIndex = e.key;
              final v = e.value;

              return Row(
                spacing: 10,
                children: [
                  if (_movingContentValueIndex != null && _movingContentValueIndex != contentValueIndex && _movingContentValueIndex != contentValueIndex - 1)
                    Button(
                      height: 500,
                      type: ButtonType.elevated,
                      isLoading: _isMovingContentValue,
                      onPressed: () async {
                        setState(() {
                          _isMovingContentValue = true;
                        });

                        await ref.watch(filesProvider.notifier).moveContentValue(widget.contentIndex, _movingContentValueIndex!, contentValueIndex);
                        if (!mounted) return;

                        setState(() {
                          _movingContentValueIndex = null;
                          _isMovingContentValue = false;
                        });
                      },
                    ),
                  SizedBox(
                    height: 500,
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: VideoContainer(key: Key(v), videoId: v),
                          ),
                          if (widget.editing)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Row(
                                children: [
                                  Button(
                                    type: ButtonType.text,
                                    icon: Icons.drive_file_move_outlined,
                                    iconSize: 24,
                                    onPressed: _movingContentValueIndex != null
                                        ? null
                                        : () {
                                            setState(() {
                                              _movingContentValueIndex = contentValueIndex;
                                              _isMovingContentValue = false;
                                            });
                                          },
                                  ),
                                  removeIcon(v, contentValueIndex),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (contentValueIndex == content.value.length - 1 && _movingContentValueIndex != null && _movingContentValueIndex != contentValueIndex)
                    Button(
                      height: 500,
                      type: ButtonType.elevated,
                      isLoading: _isMovingContentValue,
                      onPressed: () async {
                        setState(() {
                          _isMovingContentValue = true;
                        });

                        await ref.watch(filesProvider.notifier).moveContentValue(widget.contentIndex, _movingContentValueIndex!, contentValueIndex + 1);
                        if (!mounted) return;

                        setState(() {
                          _movingContentValueIndex = null;
                          _isMovingContentValue = false;
                        });
                      },
                    ),
                ],
              );
            }).toList(),
          ),
        );

      case ContentType.audioId:
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: content.value.asMap().entries.map((e) {
              final contentValueIndex = e.key;
              final v = e.value;

              return Row(
                spacing: 10,
                children: [
                  if (_movingContentValueIndex != null && _movingContentValueIndex != contentValueIndex && _movingContentValueIndex != contentValueIndex - 1)
                    Button(
                      height: 700,
                      type: ButtonType.elevated,
                      isLoading: _isMovingContentValue,
                      onPressed: () async {
                        setState(() {
                          _isMovingContentValue = true;
                        });

                        await ref.watch(filesProvider.notifier).moveContentValue(widget.contentIndex, _movingContentValueIndex!, contentValueIndex);
                        if (!mounted) return;

                        setState(() {
                          _movingContentValueIndex = null;
                          _isMovingContentValue = false;
                        });
                      },
                    ),
                  SizedBox(
                    width: 300,
                    child: Stack(
                      children: [
                        AudioContainer(key: Key(v), audioId: v),
                        if (widget.editing) Positioned(top: 4, right: 4, child: removeIcon(v, contentValueIndex)),
                      ],
                    ),
                  ),
                  if (contentValueIndex == content.value.length - 1 && _movingContentValueIndex != null && _movingContentValueIndex != contentValueIndex)
                    Button(
                      height: 700,
                      type: ButtonType.elevated,
                      isLoading: _isMovingContentValue,
                      onPressed: () async {
                        setState(() {
                          _isMovingContentValue = true;
                        });

                        await ref.watch(filesProvider.notifier).moveContentValue(widget.contentIndex, _movingContentValueIndex!, contentValueIndex + 1);
                        if (!mounted) return;

                        setState(() {
                          _movingContentValueIndex = null;
                          _isMovingContentValue = false;
                        });
                      },
                    ),
                ],
              );
            }).toList(),
          ),
        );
    }
  }
}
