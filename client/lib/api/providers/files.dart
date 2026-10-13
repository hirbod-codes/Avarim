import "dart:convert";

import "package:avarim/api/api_call.dart";
import "package:avarim/api/api_call_extensions.dart";
import "package:avarim/api/dio/dio_providers.dart";
import "package:avarim/api/dio/global_error_interceptor.dart";
import "package:avarim/api/models/folder.dart";
import "package:avarim/api/models/leaf.dart";
import "package:avarim/api/root_navigator_key.dart";
import "package:avarim/components/global/notification_service.dart";
import "package:avarim/l10n/app_localizations.dart";
import "package:avarim/lib/talker.dart";
import "package:dio/dio.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

enum FilesStateResponseStatus { success, failure }

class FilesStateResponse {
  final FilesStateResponseStatus status;
  final String? message;
  final Object? error;

  FilesStateResponse({required this.status, this.message, this.error});
}

class FilesState {
  List<Leaf>? files;
  int fileIndex;
  bool isTerm;

  FilesState({required this.files, required this.fileIndex, required this.isTerm});

  FilesState copyWith({List<Folder>? folders, List<Leaf>? files, int? folderIndex, int? fileIndex, bool? isTerm}) {
    return FilesState(files: files ?? this.files?.map((m) => m.copyWith()).toList(), fileIndex: fileIndex ?? this.fileIndex, isTerm: isTerm ?? this.isTerm);
  }

  @override
  String toString() {
    return jsonEncode({'files': files?.map((e) => e.toJson()).toList(), 'fileIndex': fileIndex, 'isTerm': isTerm});
  }
}

class Files extends Notifier<FilesState> {
  Dio get _authDio => ref.read(authDioProvider);

  @override
  FilesState build() {
    return FilesState(files: null, fileIndex: 0, isTerm: true);
  }

  void flip({bool? isTerm}) => state = state.copyWith(isTerm: isTerm ?? !state.isTerm);

  // Files
  void setFiles(List<Leaf> files) => state = state.copyWith(files: files);

  void setFileIndex(int index) => state = state.copyWith(fileIndex: index);

  Future<String?> addFile(String title, String treeNodeId) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Files.addFile is called...");
      log.debug("addFile input: title=$title, treeNodeId=$treeNodeId");

      final Map<String, dynamic> data = {"title": title, "treeNodeId": treeNodeId};

      // Send request
      final result = await apiCall(
        () => _authDio
            .post(
              "/api/leaf/",
              data: data,
              options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
            )
            .notifyOnSuccess(l10n.file_add_success),
      );
      if (result.isFailure || result.dataOrNull == null) {
        log.warning("addFile rejected: request failed or returned no data (isFailure=${result.isFailure})");
        NotificationService.showError(context: rootContext!, message: l10n.file_add_failed);
        return null;
      }

      final newId = result.dataOrNull!["id"];
      log.debug("addFile received new id=$newId");

      if (state.files == null) {
        state.files = List.from([Leaf(id: newId, treeNodeId: treeNodeId, title: title, termContents: [], definitionContents: [])]);
      } else {
        state.files!.add(Leaf(id: newId, treeNodeId: treeNodeId, title: title, termContents: [], definitionContents: []));
        state = state.copyWith();
      }

      log.info("addFile succeeded: id=$newId, treeNodeId=$treeNodeId");
      return newId;
    } catch (e) {
      log.error("Files.addFile throws an error", e);
      NotificationService.showError(context: rootContext!, message: l10n.file_add_failed);
      return null;
    } finally {
      log.info("Files.addFile call ended");
    }
  }

  Future<bool> removeFile(int index) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Files.removeFile is called...");
      log.debug("removeFile input: index=$index");

      if (state.files == null) {
        log.warning("removeFile rejected: no files loaded in state");
        NotificationService.showError(message: l10n.files_not_found);
        return false;
      }
      if (index >= state.files!.length || index < 0) {
        log.warning("removeFile rejected: index=$index out of range (length=${state.files!.length})");
        NotificationService.showError(message: l10n.file_not_found);
        return false;
      }

      final targetId = state.files![index].id;
      log.debug("removeFile resolved id=$targetId for index=$index");

      final result = await apiCall(
        () => _authDio
            .delete('/api/leaf/?id=$targetId', options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}))
            .notifyOnSuccess(l10n.file_remove_success),
      );
      if (result.isFailure) {
        log.warning("removeFile rejected: request failed for id=$targetId");
        NotificationService.showError(message: l10n.file_remove_failed);
        return false;
      }

      state.files!.removeAt(index);
      state = state.copyWith();

      log.info("removeFile succeeded: id=$targetId, index=$index");
      return true;
    } catch (e) {
      log.error("Files.removeFile throws an error", e);
      NotificationService.showError(message: l10n.file_remove_failed);
      return false;
    } finally {
      log.info("Files.removeFile call ended");
    }
  }

  Future<bool> removeFileById(String id) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Files.removeFileById is called...");
      log.debug("removeFileById input: id=$id");

      if (state.files == null) {
        log.warning("removeFileById rejected: no files loaded in state");
        NotificationService.showError(message: l10n.files_not_found);
        return false;
      }

      int? fileIndex;
      for (int i = 0; i < state.files!.length; i++) {
        if (state.files![i].id != id) continue;
        fileIndex = i;
        break;
      }
      if (fileIndex == null) {
        log.warning("removeFileById rejected: file id=$id not found in state");
        NotificationService.showError(message: l10n.file_not_found);
        return false;
      }
      log.debug("removeFileById resolved fileIndex=$fileIndex");

      final result = await apiCall(
        () => _authDio
            .delete('/api/leaf/?id=$id', options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}))
            .notifyOnSuccess(l10n.file_remove_success),
      );
      if (result.isFailure) {
        log.warning("removeFileById rejected: request failed for id=$id");
        NotificationService.showError(message: l10n.file_remove_failed);
        return false;
      }

      state.files!.removeWhere((f) => f.id == id);
      state = state.copyWith();

      log.info("removeFileById succeeded: id=$id");
      return true;
    } catch (e) {
      log.error("Files.removeFileById throws an error", e);
      NotificationService.showError(message: l10n.file_remove_failed);
      return false;
    } finally {
      log.info("Files.removeFileById call ended");
    }
  }

  Future<bool> moveFile(Leaf file, String destId) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Files.moveFile is called...");
      log.debug("moveFile input: id=${file.id}, destId=$destId");

      ApiCallResult<dynamic> result = await apiCall(
        () => _authDio
            .put(
              '/api/leaf',
              data: {'leafId': file.id, 'treeNodeId': destId},
              options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
            )
            .notifyOnSuccess(l10n.file_move_success),
      );
      if (result.isFailure) {
        log.warning("moveFile rejected: request failed for id=${file.id}, destId=$destId");
        NotificationService.showError(context: rootContext!, message: l10n.file_move_failed);
        return false;
      }

      log.info("moveFile succeeded: id=${file.id}, destId=$destId");
      return true;
    } catch (e) {
      log.error("Files.moveFile throws an error", e);
      NotificationService.showError(context: rootContext!, message: l10n.file_move_failed);
      return false;
    } finally {
      log.info("Files.moveFile call ended");
    }
  }

  // Contents
  Future<bool> addContent(Content content, {int? atIndex}) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Files.addContent is called...");
      log.debug("addContent input: isTerm=${state.isTerm}");

      if (state.files == null) {
        log.warning("addContent rejected: no files loaded in state");
        NotificationService.showError(message: l10n.files_not_found);
        return false;
      }

      // Create temporary data
      final tempFile = state.files![state.fileIndex].copyWith();
      final List<Content> contents;
      if (state.isTerm) {
        contents = tempFile.termContents.map((m) => m.copyWith()).toList();
      } else {
        contents = tempFile.definitionContents.map((m) => m.copyWith()).toList();
      }

      // Update
      contents.add(content);
      log.debug("addContent appended entry, new length=${contents.length}");

      ApiCallResult<dynamic> result = await apiCall(
        () => _authDio
            .post(
              '/api/leaf/content',
              data: {
                'leafId': tempFile.id,
                'type': content.type.name,
                'isTerm': state.isTerm,
                ...(atIndex == null ? {} : {'atIndex': atIndex}),
              },
              options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
            )
            .notifyOnSuccess(l10n.content_add_success),
      );
      if (result.isFailure) {
        log.warning("addContent rejected: request failed for fileId=${tempFile.id}");
        NotificationService.showError(context: rootContext!, message: l10n.content_add_failed);
        return false;
      }

      if (state.isTerm) {
        state.files![state.fileIndex].termContents = contents;
      } else {
        state.files![state.fileIndex].definitionContents = contents;
      }

      state = state.copyWith();

      log.info("addContent succeeded: fileId=${tempFile.id}, isTerm=${state.isTerm}");
      return true;
    } catch (e) {
      log.error("Files.addContent throws an error", e);
      NotificationService.showError(context: rootContext!, message: l10n.content_add_failed);
      return false;
    } finally {
      log.info("Files.addContent call ended");
    }
  }

  Future<bool> removeContent(int index) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Files.removeContent is called...");
      log.debug("removeContent input: index=$index, isTerm=${state.isTerm}");

      if (state.files == null) {
        log.warning("removeContent rejected: no files loaded in state");
        NotificationService.showError(message: l10n.files_not_found);
        return false;
      }

      // Create temporary data
      final tempFile = state.files![state.fileIndex].copyWith();
      final List<Content> contents;
      if (state.isTerm) {
        contents = tempFile.termContents.map((m) => m.copyWith()).toList();
      } else {
        contents = tempFile.definitionContents.map((m) => m.copyWith()).toList();
      }

      // Update
      contents.removeAt(index);
      log.debug("removeContent removed entry at index=$index, new length=${contents.length}");

      ApiCallResult<dynamic> result = await apiCall(
        () => _authDio
            .delete(
              '/api/leaf/content',
              data: {'leafId': tempFile.id, 'type': 'imageId', 'isTerm': state.isTerm, 'atIndex': index},
              options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
            )
            .notifyOnSuccess(l10n.content_add_success),
      );
      if (result.isFailure) {
        log.warning("removeContent rejected: request failed for fileId=${tempFile.id}, index=$index");
        NotificationService.showError(context: rootContext!, message: l10n.content_remove_failed);
        return false;
      }

      if (state.isTerm) {
        state.files![state.fileIndex].termContents = contents;
      } else {
        state.files![state.fileIndex].definitionContents = contents;
      }

      state = state.copyWith();

      log.info("removeContent succeeded: fileId=${tempFile.id}, index=$index");
      return true;
    } catch (e) {
      log.error("Files.removeContent throws an error", e);
      NotificationService.showError(context: rootContext!, message: l10n.content_remove_failed);
      return false;
    } finally {
      log.info("Files.removeContent call ended");
    }
  }

  Future<bool> setContentValue(String value, int contentIndex, int contentValueIndex) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Files.setContentValue is called...");
      log.debug("setContentValue input: contentIndex=$contentIndex, contentValueIndex=$contentValueIndex, isTerm=${state.isTerm}");

      if (state.files == null) {
        log.warning("setContentValue rejected: no files loaded in state");
        NotificationService.showError(message: l10n.files_not_found);
        return false;
      }

      // Create temporary data
      final tempFile = state.files![state.fileIndex].copyWith();
      final List<Content> contents;
      if (state.isTerm) {
        if (contentIndex < 0 ||
            contentValueIndex < 0 ||
            contentIndex >= state.files![state.fileIndex].termContents.length ||
            contentValueIndex >= state.files![state.fileIndex].termContents[contentIndex].value.length) {
          log.warning("setContentValue rejected: contentIndex=$contentIndex or contentValueIndex=$contentValueIndex out of range (termContents)");
          NotificationService.showError(message: l10n.file_not_found);
          return false;
        }
        contents = tempFile.termContents;
      } else {
        if (contentIndex < 0 ||
            contentValueIndex < 0 ||
            contentIndex >= state.files![state.fileIndex].definitionContents.length ||
            contentValueIndex >= state.files![state.fileIndex].definitionContents[contentIndex].value.length) {
          log.warning("setContentValue rejected: contentIndex=$contentIndex or contentValueIndex=$contentValueIndex out of range (definitionContents)");
          NotificationService.showError(message: l10n.file_not_found);
          return false;
        }
        contents = tempFile.definitionContents;
      }

      // Update
      String type = contents[contentIndex].type.name;
      contents[contentIndex].value[contentValueIndex] = value;
      log.debug("setContentValue updated value of type=$type at contentIndex=$contentIndex, contentValueIndex=$contentValueIndex");

      ApiCallResult<dynamic> addResult = await apiCall(
        () => _authDio
            .put(
              '/api/leaf/content/value',
              data: {
                'leafId': tempFile.id,
                'type': type,
                'isTerm': state.isTerm,
                'atContentIndex': contentIndex,
                'value': value,
                'atContentValueIndex': contentValueIndex,
              },
              options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
            )
            .notifyOnSuccess(l10n.content_value_set_success),
      );
      if (addResult.isFailure) {
        log.warning("setContentValue rejected: request failed for fileId=${tempFile.id}");
        NotificationService.showError(context: rootContext!, message: l10n.content_value_set_failed);
        return false;
      }

      if (state.isTerm) {
        state.files![state.fileIndex].termContents = contents;
      } else {
        state.files![state.fileIndex].definitionContents = contents;
      }

      state = state.copyWith();

      log.info("setContentValue succeeded: fileId=${tempFile.id}, contentIndex=$contentIndex, contentValueIndex=$contentValueIndex");
      return true;
    } catch (e) {
      log.error("Files.setContentValue throws an error", e);
      NotificationService.showError(context: rootContext!, message: l10n.content_value_set_failed);
      return false;
    } finally {
      log.info("Files.setContentValue call ended");
    }
  }

  Future<bool> addContentValue(String value, int contentIndex, {int? contentValueIndex}) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Files.addContentValue is called...");
      log.debug({'state': state, 'value': value, 'contentIndex': contentIndex, 'contentValueIndex': contentValueIndex});

      if (state.files == null) {
        log.warning("addContentValue rejected: no files loaded in state");
        NotificationService.showError(message: l10n.files_not_found);
        return false;
      }

      // Create temporary data
      final tempFile = state.files![state.fileIndex].copyWith();
      final List<Content> contents;
      if (state.isTerm) {
        contents = tempFile.termContents.map((m) => m.copyWith()).toList();
      } else {
        contents = tempFile.definitionContents.map((m) => m.copyWith()).toList();
      }

      // Update
      String type = contents[contentIndex].type.name;
      if (contentValueIndex != null) {
        contents[contentIndex].value.insert(contentValueIndex, value);
      } else {
        contents[contentIndex].value.add(value);
      }
      log.debug("addContentValue appended value at contentIndex=$contentIndex, new value length=${contents[contentIndex].value.length}");

      ApiCallResult<dynamic> result = await apiCall(
        () => _authDio
            .post(
              '/api/leaf/content/value',
              data: {
                'leafId': tempFile.id,
                'type': type,
                'isTerm': state.isTerm,
                'atContentIndex': contentIndex,
                'value': value,
                ...(contentValueIndex == null ? {} : {'atContentValueIndex': contentValueIndex}),
              },
              options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
            )
            .notifyOnSuccess(l10n.content_value_set_success),
      );
      if (result.isFailure) {
        log.warning("addContentValue rejected: request failed for fileId=${tempFile.id}, contentIndex=$contentIndex");
        NotificationService.showError(context: rootContext!, message: l10n.content_value_add_failed);
        return false;
      }

      if (state.isTerm) {
        state.files![state.fileIndex].termContents = contents;
      } else {
        state.files![state.fileIndex].definitionContents = contents;
      }

      state = state.copyWith();

      log.info("addContentValue succeeded: fileId=${tempFile.id}, contentIndex=$contentIndex");
      return true;
    } catch (e) {
      log.error("Files.addContentValue throws an error", e);
      NotificationService.showError(context: rootContext!, message: l10n.content_value_add_failed);
      return false;
    } finally {
      log.info("Files.addContentValue call ended");
    }
  }

  Future<bool> removeContentValue(int contentIndex, int valueIndex) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Files.removeContentValue is called...");
      log.debug("removeContentValue input: contentIndex=$contentIndex, valueIndex=$valueIndex, isTerm=${state.isTerm}");

      if (state.files == null) {
        log.warning("removeContentValue rejected: no files loaded in state");
        NotificationService.showError(message: l10n.files_not_found);
        return false;
      }

      // Create temporary data
      final tempFile = state.files![state.fileIndex].copyWith();
      final List<Content> contents;
      if (state.isTerm) {
        contents = tempFile.termContents.map((m) => m.copyWith()).toList();
      } else {
        contents = tempFile.definitionContents.map((m) => m.copyWith()).toList();
      }

      // Update
      String type = contents[contentIndex].type.name;
      contents[contentIndex].value.removeAt(valueIndex);
      log.debug(
        "removeContentValue removed value at contentIndex=$contentIndex, valueIndex=$valueIndex, new value length=${contents[contentIndex].value.length}",
      );

      ApiCallResult<dynamic> result = await apiCall(
        () => _authDio
            .delete(
              '/api/leaf/content/value',
              data: {'leafId': tempFile.id, 'type': type, 'isTerm': state.isTerm, 'atContentIndex': contentIndex, 'atContentValueIndex': valueIndex},
              options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
            )
            .notifyOnSuccess(l10n.content_value_remove_success),
      );
      if (result.isFailure) {
        log.warning("removeContentValue rejected: request failed for fileId=${tempFile.id}, contentIndex=$contentIndex");
        NotificationService.showError(context: rootContext!, message: l10n.content_value_remove_failed);
        return false;
      }

      if (state.isTerm) {
        state.files![state.fileIndex].termContents = contents;
      } else {
        state.files![state.fileIndex].definitionContents = contents;
      }

      state = state.copyWith();

      log.info("removeContentValue succeeded: fileId=${tempFile.id}, contentIndex=$contentIndex, valueIndex=$valueIndex");
      return true;
    } catch (e) {
      log.error("Files.removeContentValue throws an error", e);
      NotificationService.showError(context: rootContext!, message: l10n.content_value_remove_failed);
      return false;
    } finally {
      log.info("Files.removeContentValue call ended");
    }
  }

  Future<bool> moveContent(int fromIndex, int toIndex) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Files.moveContent is called...");
      log.debug("moveContent input: fromIndex=$fromIndex, toIndex=$toIndex, isTerm=${state.isTerm}");

      if (toIndex < 0 || fromIndex < 0) {
        log.warning("moveContent rejected: invalid index provided (fromIndex=$fromIndex, toIndex=$toIndex)");
        NotificationService.showError(message: l10n.content_move_failed);
        return false;
      }

      if (state.files == null || state.files!.isEmpty) {
        log.warning("moveContent rejected: no files loaded in state");
        NotificationService.showError(message: l10n.files_not_found);
        return false;
      }

      final file = state.files![state.fileIndex].copyWith();

      final contents = state.isTerm ? file.termContents : file.definitionContents;

      if (toIndex > contents.length || fromIndex >= contents.length) {
        log.warning("moveContent rejected: invalid index provided (fromIndex=$fromIndex, toIndex=$toIndex, length=${contents.length})");
        NotificationService.showError(message: l10n.files_not_found);
        return false;
      }

      final fromContent = contents.removeAt(fromIndex);

      if (toIndex > fromIndex) toIndex--; // because one item is removed, therefor the total length is reduced by one.

      contents.insert(toIndex, fromContent);
      log.debug("moveContent reordered: fromIndex=$fromIndex, resolvedToIndex=$toIndex, fileId=${file.id}");

      ApiCallResult<dynamic> result = await apiCall(
        () => _authDio
            .put(
              '/api/leaf/',
              data: {'leafId': file.id, state.isTerm ? 'termContents' : 'definitionContents': contents},
              options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
            )
            .notifyOnSuccess(l10n.content_add_success),
      );
      if (result.isFailure) {
        log.warning("moveContent rejected: request failed to add content for fileId=${file.id}");
        NotificationService.showError(context: rootContext!, message: l10n.content_add_failed);
        return false;
      }

      if (state.isTerm) state.files![state.fileIndex].termContents = contents;
      if (!state.isTerm) state.files![state.fileIndex].definitionContents = contents;

      state = state.copyWith();

      log.info("moveContent succeeded: fileId=${file.id}, fromIndex=$fromIndex, toIndex=$toIndex");
      return true;
    } catch (e) {
      log.error("Files.moveContent throws an error", e);
      NotificationService.showError(message: l10n.content_move_failed);
      return false;
    } finally {
      log.info("Files.moveContent call ended");
    }
  }

  Future<bool> moveContentValue(int contentIndex, int fromIndex, int toIndex) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Files.moveContentValue is called...");
      log.debug("moveContentValue input: contentIndex=$contentIndex, fromIndex=$fromIndex, toIndex=$toIndex, isTerm=${state.isTerm}");

      if (contentIndex < 0 || toIndex < 0 || fromIndex < 0) {
        log.warning("moveContentValue rejected: invalid index provided (contentIndex=$contentIndex, fromIndex=$fromIndex, toIndex=$toIndex)");
        NotificationService.showError(message: l10n.content_move_failed);
        return false;
      }

      if (state.files == null || state.files!.isEmpty) {
        log.warning("moveContentValue rejected: no files loaded in state");
        NotificationService.showError(message: l10n.files_not_found);
        return false;
      }

      final file = state.files![state.fileIndex].copyWith();

      final contents = state.isTerm ? file.termContents : file.definitionContents;

      if (contentIndex >= contents.length) {
        log.warning("moveContentValue rejected: content not found (contentIndex=$contentIndex, length=${contents.length})");
        NotificationService.showError(message: l10n.content_not_found);
        return false;
      }

      final content = contents[contentIndex];

      if (toIndex > content.value.length || fromIndex >= content.value.length) {
        log.warning("moveContentValue rejected: content value not found (fromIndex=$fromIndex, toIndex=$toIndex, length=${content.value.length})");
        NotificationService.showError(message: l10n.content_not_found);
        return false;
      }

      final fromContentValue = content.value.removeAt(fromIndex);

      if (toIndex > fromIndex) toIndex--; // because one item is removed, therefor the total length is reduced by one.

      content.value.insert(toIndex, fromContentValue);
      log.debug("moveContentValue reordered: contentIndex=$contentIndex, fromIndex=$fromIndex, resolvedToIndex=$toIndex, fileId=${file.id}");

      ApiCallResult<dynamic> result = await apiCall(
        () => _authDio
            .put(
              '/api/leaf/content/',
              data: {'leafId': file.id, 'isTerm': state.isTerm, 'atIndex': contentIndex, 'content': content},
              options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true}),
            )
            .notifyOnSuccess(l10n.content_add_success),
      );
      if (result.isFailure) {
        log.warning("moveContent rejected: request failed to add content for fileId=${file.id}");
        NotificationService.showError(context: rootContext!, message: l10n.content_add_failed);
        return false;
      }

      if (state.isTerm) state.files![state.fileIndex].termContents[contentIndex] = content;
      if (!state.isTerm) state.files![state.fileIndex].definitionContents[contentIndex] = content;

      state = state.copyWith();

      log.info("moveContentValue succeeded: fileId=${file.id}, contentIndex=$contentIndex, fromIndex=$fromIndex, toIndex=$toIndex");
      return true;
    } catch (e) {
      log.error("Files.moveContentValue throws an error", e);
      NotificationService.showError(message: l10n.content_move_failed);
      return false;
    } finally {
      log.info("Files.moveContentValue call ended");
    }
  }
}

final filesProvider = NotifierProvider<Files, FilesState>(Files.new);
