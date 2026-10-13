import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/models/folder.dart';
import 'package:avarim/api/models/leaf.dart';
import 'package:avarim/api/providers/files.dart';
import 'package:avarim/api/providers/folders.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/components/dialogs/folder_file_create_dialog.dart';
import 'package:avarim/components/file_manager.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/theme/app_colors.dart';
import 'package:avarim/theme/theme_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/lib/talker.dart';

class AppPage extends StatelessWidget {
  const AppPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width < 600) {
      return const MobileAppPage();
    }

    // Tablet
    if (width < 1024) {
      return const MobileAppPage();
    }

    return MobileAppPage();
  }
}

enum Filter { folder, file }

class MobileAppPage extends ConsumerStatefulWidget {
  const MobileAppPage({super.key});

  @override
  ConsumerState<MobileAppPage> createState() => _MobileAppPage();
}

class _MobileAppPage extends ConsumerState<MobileAppPage> {
  final TextEditingController _searchController = TextEditingController();
  Filter _filter = Filter.folder;

  int _folderSkip = 0;
  int _fileSkip = 0;
  bool _hasMore = true;

  Timer? _debouncer;
  String _search = '';

  Folder? _movingFolder;
  bool _isMovingFolder = false;
  Leaf? _movingFile;
  bool _isMovingFile = false;

  bool _fetching = false;
  bool _adding = false;

  String? _title;

  final List<String> _location = ['root'];

  bool _editing = false;

  int _deletingFolder = -1;
  int _deletingFile = -1;

  @override
  void dispose() {
    _debouncer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;
    _initialized = true;

    // Runs once when the widget is inserted
    _initialize();
  }

  Future<void> _initialize() async => await _paginate(reset: true);

  void _resetSearch() {
    _debouncer?.cancel();
    _search = '';
    _searchController.clear();
    _hasMore = true;
  }

  Future<void> _goToRoot() async {
    await _paginate(reset: true, filter: Filter.folder);
    if (!mounted) return;

    setState(() {
      _location.removeLast();
      _title = null;
      ref.read(filesProvider.notifier).setFiles([]);
      _filter = Filter.folder;
      _resetSearch();
    });
  }

  Future<void> _goTo(String locationId) async {
    final result = await apiCall<Folder?>(
      () => ref.read(authDioProvider).get('/api/treeNode/?treeNodeId=$locationId'),
      fromJson: (data) => Folder.fromJson(data),
    );
    if (!mounted) return;

    if (result.isFailure || result.dataOrNull == null) {
      await _goToRoot();
      return;
    }

    await _paginate(parentId: locationId, reset: true);
    if (!mounted) return;

    setState(() {
      _title = result.dataOrNull!.title;
      _location.removeLast();
      _resetSearch();
    });
  }

  Future<void> _previousLocation() async {
    if (_location.length < 2) return;

    setState(() {
      _fetching = true;
    });

    final lastId = _location.elementAt(_location.length - 2);
    if (lastId == 'root') {
      await _goToRoot();
    } else {
      await _goTo(lastId);
    }
  }

  Future<void> _nextLocation(Folder parentFolder) async {
    setState(() {
      _fetching = true;
    });

    await _paginate(parentId: parentFolder.id, reset: true);

    if (!mounted) return;
    setState(() {
      _title = parentFolder.title;
      _location.add(parentFolder.id);
      _fetching = false;
      _search = '';
    });
  }

  void _onSearchChange(String value) {
    setState(() {
      _search = value;
    });

    _debouncer = Timer(Duration(milliseconds: 700), () {
      _paginate(search: value, reset: true);
    });
  }

  Future<void> _paginate({String? search, int limit = 10, String? parentId, bool reset = false, Filter? filter}) async {
    if (!reset && !_hasMore) return;

    AppLocalizations l10n = AppLocalizations.of(context)!;

    try {
      filter = filter ?? _filter;

      setState(() {
        _fetching = true;
      });

      if (_location.length == 1 || filter == Filter.folder) {
        final skip = reset ? 0 : _folderSkip;
        final result = await apiCall<List<Folder>>(
          () => ref
              .read(authDioProvider)
              .get(
                '/api/treeNode/list/?limit=$limit${'&skip=$skip'}${parentId != null ? '&parentId=$parentId' : ''}${search != null ? '&search=$search' : ''}',
              ),
          fromJson: (data) => List.from(data).map((e) => Folder.fromJson(e)).toList(),
        );
        if (!mounted) return;
        if (result.isFailure || result.dataOrNull == null) {
          return;
        }

        final folders = result.dataOrNull!;

        setState(() {
          _hasMore = folders.length >= limit;

          if (reset) {
            _folderSkip = folders.length;
            ref.read(foldersProvider.notifier).setFolders(folders);
          } else {
            _folderSkip = folders.length + _folderSkip;
            ref.read(foldersProvider.notifier).setFolders([...(ref.read(foldersProvider).folders ?? []), ...folders]);
          }
        });
      } else if (filter == Filter.file) {
        final skip = reset ? 0 : _fileSkip;

        final result = await apiCall<List<Leaf>>(
          () => ref.read(authDioProvider).get('/api/leaf/list/?limit=$limit&parentId=$parentId${'&skip=$skip'}${search != null ? '&search=$search' : ''}'),
          fromJson: (data) => List.from(data).map((e) => Leaf.fromJson(e)).toList(),
        );
        if (!mounted) return;
        if (result.isFailure || result.dataOrNull == null) {
          return;
        }

        final files = result.dataOrNull!;

        setState(() {
          _hasMore = files.length >= limit;

          if (reset) {
            _fileSkip = files.length;
            ref.read(filesProvider.notifier).setFiles(files);
          } else {
            _fileSkip = files.length + _fileSkip;
            ref.read(filesProvider.notifier).setFiles([...(ref.read(filesProvider).files ?? []), ...files]);
          }
        });
      }
    } catch (e) {
      talker.error('The _paginate method in AppPage widget threw an error.', e);
      NotificationService.showError(message: filter == Filter.file ? l10n.app_page_file_pagination_failed : l10n.app_page_folder_pagination_failed);
    } finally {
      if (mounted) {
        setState(() {
          _fetching = false;
        });
      }
    }
  }

  Future<void> _paginateMore() async {
    await _paginate(search: _search, parentId: _location.last == 'root' ? null : _location.last);
  }

  Future<void> _onFilterChange(Filter filter) async {
    if (_location.length < 2) return;

    final lastId = _location.last;
    if (lastId == 'root') return;

    setState(() {
      _fetching = true;
      _filter = filter;
    });

    await _paginate(parentId: lastId, reset: true);

    if (!mounted) return;
    setState(() {
      _resetSearch();
    });
  }

  Future<void> _removeFolder(Folder folder, int index) async {
    setState(() {
      _deletingFolder = index;
    });

    await ref.read(foldersProvider.notifier).removeFolderById(folder.id);
    if (!mounted) return;

    setState(() {
      _deletingFolder = -1;
      ref.read(foldersProvider.notifier).removeFolderById(folder.id);
    });
  }

  Future<void> _removeFile(Leaf file, int index) async {
    setState(() {
      _deletingFile = index;
    });

    await ref.read(filesProvider.notifier).removeFileById(file.id);
    if (!mounted) return;

    setState(() {
      _deletingFile = -1;
      ref.read(filesProvider.notifier).removeFileById(file.id);
    });
  }

  Future<void> _addNew() async {
    if (_adding) return;

    setState(() {
      _adding = true;
    });

    try {
      String? title = await showDialog(
        context: context,
        builder: (builderContext) {
          return FolderFileCreateDialog();
        },
      );
      if (title == null) return;

      if (_location.last == 'root' || _filter == Filter.folder) {
        await ref.read(foldersProvider.notifier).addFolder(title, _location.last == 'root' ? null : _location.last);
      } else {
        await ref.read(filesProvider.notifier).addFile(title, _location.last);
      }
    } finally {
      if (mounted) {
        setState(() {
          _adding = false;
        });
      }
    }
  }

  void _moveFolder() async {
    setState(() {
      _isMovingFolder = true;
    });

    await ref.read(foldersProvider.notifier).moveFolder(_movingFolder!, _location.last == 'root' ? null : _location.last);
    if (!mounted) return;

    ref.read(foldersProvider.notifier).setFolders([...(ref.read(foldersProvider).folders ?? []), _movingFolder!]);

    setState(() {
      _isMovingFolder = false;
      _movingFolder = null;
    });
  }

  void _moveFile() async {
    if (_location.last == 'root') return;

    setState(() {
      _isMovingFile = true;
    });

    await ref.read(filesProvider.notifier).moveFile(_movingFile!, _location.last);
    if (!mounted) return;

    ref.read(filesProvider.notifier).setFiles([...(ref.read(filesProvider).files ?? []), _movingFile!]);

    setState(() {
      _isMovingFile = false;
      _movingFile = null;
    });
  }

  void _cancelMove() {
    setState(() {
      _movingFolder = null;
      _isMovingFolder = false;
      _movingFile = null;
      _isMovingFile = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final foldersState = ref.watch(foldersProvider);
    final folders = foldersState.folders ?? [];

    final filesNotifier = ref.watch(filesProvider.notifier);
    final filesState = ref.watch(filesProvider);
    final files = filesState.files;

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final spacing = getSpacing(maxWidth);

        return Card(
          elevation: 10,
          color: theme.colorScheme.surfaceContainer,
          child: Padding(
            padding: EdgeInsets.all(spacing.padding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Buttons
                Row(
                  mainAxisAlignment: _location.length > 1 ? MainAxisAlignment.spaceBetween : MainAxisAlignment.end,
                  children: [
                    // Back Button
                    if (_location.length > 1) ...[
                      Button(type: ButtonType.text, iconSize: 28, isLoading: _fetching, icon: Icons.chevron_left, onPressed: _previousLocation),
                    ],
                    // Edit Button
                    Button(
                      type: ButtonType.text,
                      iconSize: 24,
                      icon: _editing ? Icons.remove_red_eye_outlined : Icons.edit_square,
                      onPressed: () {
                        setState(() {
                          _editing = !_editing;
                        });
                      },
                    ),
                  ],
                ),

                // Title
                SizedBox(height: spacing.listItemSpacing),
                if (_title != null) ...[Text(_title!, style: TextStyle(fontSize: 30)), Divider(height: 1, color: theme.colorScheme.outlineVariant)],

                // Search
                SizedBox(height: spacing.listItemSpacing),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(labelText: l10n.search, prefixIcon: Icon(Icons.search)),
                  onChanged: _onSearchChange,
                ),

                // Add new Button
                if (_editing) SizedBox(height: spacing.listItemSpacing),
                if (_editing)
                  Button(
                    type: ButtonType.elevated,
                    color: theme.extension<AppColors>()!.success,
                    icon: Icons.add,
                    label: l10n.addNew,
                    onPressed: _addNew,
                    isLoading: _adding,
                  ),

                // Move buttons
                if (_movingFolder != null || _movingFile != null) SizedBox(height: spacing.listItemSpacing),
                if (_movingFolder != null || _movingFile != null)
                  Row(
                    children: [
                      Button(
                        type: ButtonType.elevated,
                        color: theme.extension<AppColors>()!.success,
                        label: l10n.moveHere,
                        onPressed:
                            ((_movingFolder != null && _location.last == _movingFolder!.parentId) ||
                                (_movingFile != null && (_location.last == 'root' || _location.last == _movingFile!.treeNodeId)))
                            ? null
                            : (_movingFolder != null ? _moveFolder : _moveFile),
                        isLoading: _isMovingFolder || _isMovingFile,
                      ),
                      Button(type: ButtonType.elevated, color: theme.colorScheme.error, label: l10n.cancelMove, onPressed: _cancelMove),
                    ],
                  ),

                SizedBox(height: spacing.groupSpacing),

                // Tabs
                if (_location.length > 1) ...[
                  Container(
                    decoration: BoxDecoration(
                      border: BoxBorder.fromLTRB(bottom: BorderSide(width: 1, color: theme.colorScheme.outlineVariant)),
                    ),
                    child: Row(
                      spacing: spacing.listItemSpacing,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: _filter == Filter.folder
                                ? BoxBorder.fromLTRB(bottom: BorderSide(width: 5, color: theme.colorScheme.primary))
                                : BoxBorder.fromLTRB(bottom: BorderSide(width: 5, color: Colors.transparent)),
                          ),
                          child: Button(
                            label: l10n.categories,
                            width: 100,
                            height: 40,
                            radius: 0,
                            type: ButtonType.text,
                            color: _filter == Filter.folder ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                            onPressed: () {
                              _onFilterChange(Filter.folder);
                            },
                          ),
                        ),

                        Container(
                          decoration: BoxDecoration(
                            border: _filter == Filter.file
                                ? BoxBorder.fromLTRB(bottom: BorderSide(width: 5, color: theme.colorScheme.primary))
                                : BoxBorder.fromLTRB(bottom: BorderSide(width: 5, color: Colors.transparent)),
                          ),
                          child: Button(
                            label: l10n.cards,
                            width: 100,
                            height: 40,
                            radius: 0,
                            type: ButtonType.text,
                            color: _filter == Filter.file ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                            onPressed: _movingFolder != null
                                ? null
                                : () {
                                    _onFilterChange(Filter.file);
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                SizedBox(height: spacing.listItemSpacing),

                // Lists
                Expanded(
                  child: ListView(
                    children: [
                      // Circular progress indicator
                      if (_fetching)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary))],
                        ),

                      // Folders list
                      if (!_fetching)
                        if (_location.length == 1 || _filter == Filter.folder)
                          ListView.separated(
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            itemCount: folders.length,
                            separatorBuilder: (context, index) => SizedBox(height: spacing.listItemSpacing),
                            itemBuilder: (context, index) => Card(
                              clipBehavior: Clip.hardEdge,
                              child: InkWell(
                                onTap: () {
                                  _nextLocation(folders[index]);
                                },
                                child: Padding(
                                  padding: EdgeInsetsGeometry.all(8),
                                  child: ListTile(
                                    title: Text(folders[index].title),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_editing) ...[
                                          Button(
                                            type: ButtonType.text,
                                            color: theme.colorScheme.error,
                                            icon: Icons.remove_circle_outline,
                                            isLoading: _deletingFolder == index,
                                            onPressed: () {
                                              _removeFolder(folders[index], index);
                                            },
                                          ),
                                        ],
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert),
                                          onSelected: (value) {
                                            switch (value) {
                                              case 'move':
                                                setState(() {
                                                  _movingFolder = folders[index].copyWith();
                                                  _isMovingFolder = false;
                                                });
                                                break;
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'move',
                                              child: ListTile(
                                                leading: Icon(Icons.drive_file_move_outlined),
                                                title: Text(l10n.move),
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                      // Files list
                      if (!_fetching)
                        if (_location.length > 1 && _filter == Filter.file && files != null && files.isNotEmpty)
                          ListView.separated(
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            itemCount: files.length,
                            separatorBuilder: (context, index) => SizedBox(height: spacing.listItemSpacing),
                            itemBuilder: (context, index) {
                              final file = files[index];
                              return Card(
                                clipBehavior: Clip.hardEdge,
                                child: InkWell(
                                  onTap: () {
                                    filesNotifier.setFileIndex(index);
                                    showDialog(
                                      context: context,
                                      barrierDismissible: true,
                                      builder: (_) {
                                        return LayoutBuilder(
                                          builder: (context, constraints) {
                                            final maxWidth = constraints.maxWidth;
                                            final spacing = getSpacing(maxWidth);

                                            return Padding(
                                              padding: EdgeInsets.all(spacing.padding),
                                              child: FileManager(
                                                file: file,
                                                onClose: () {
                                                  Navigator.of(context).pop();
                                                },
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                  child: Padding(
                                    padding: EdgeInsetsGeometry.all(8),
                                    child: ListTile(
                                      title: Text(file.title),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_editing) ...[
                                            Button(
                                              isLoading: _deletingFile == index,
                                              type: ButtonType.text,
                                              color: theme.colorScheme.error,
                                              icon: Icons.remove_circle_outline,
                                              onPressed: () {
                                                _removeFile(file, index);
                                              },
                                            ),
                                          ],
                                          PopupMenuButton<String>(
                                            icon: const Icon(Icons.more_vert),
                                            onSelected: (value) {
                                              switch (value) {
                                                case 'move':
                                                  setState(() {
                                                    _movingFile = files[index].copyWith();
                                                    _isMovingFile = false;
                                                  });
                                                  break;
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              PopupMenuItem(
                                                value: 'move',
                                                child: ListTile(
                                                  leading: Icon(Icons.drive_file_move_outlined),
                                                  title: Text(l10n.move),
                                                  contentPadding: EdgeInsets.zero,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                    ],
                  ),
                ),

                if (_hasMore) SizedBox(height: spacing.groupSpacing),

                if (_hasMore)
                  Button(
                    label: l10n.loadMore,
                    type: ButtonType.outlined,
                    color: theme.colorScheme.secondary,
                    onPressed: () {
                      _paginateMore();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
