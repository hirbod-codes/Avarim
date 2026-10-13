import "dart:convert";

import "package:avarim/api/api_call.dart";
import "package:avarim/api/api_call_extensions.dart";
import "package:avarim/api/dio/dio_providers.dart";
import "package:avarim/api/models/folder.dart";
import "package:avarim/api/models/leaf.dart";
import "package:avarim/api/root_navigator_key.dart";
import "package:avarim/components/global/notification_service.dart";
import "package:avarim/l10n/app_localizations.dart";
import "package:dio/dio.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:avarim/lib/talker.dart";

enum FoldersStateResponseStatus { success, failure }

class FoldersStateResponse {
  final FoldersStateResponseStatus status;
  final String? message;
  final Object? error;

  FoldersStateResponse({required this.status, this.message, this.error});
}

class FoldersState {
  List<Folder>? folders;
  int folderIndex;
  bool isTerm;

  FoldersState({required this.folders, required this.folderIndex, required this.isTerm});

  FoldersState copyWith({List<Folder>? folders, List<Leaf>? files, int? folderIndex, int? fileIndex, bool? isTerm}) {
    return FoldersState(
      folders: folders ?? this.folders?.map((m) => m.copyWith()).toList(),
      folderIndex: folderIndex ?? this.folderIndex,
      isTerm: isTerm ?? this.isTerm,
    );
  }

  @override
  String toString() {
    return jsonEncode({'folders': folders?.map((e) => e.toJson()).toList(), 'folderIndex': folderIndex, 'isTerm': isTerm});
  }
}

class Folders extends Notifier<FoldersState> {
  Dio get _authDio => ref.read(authDioProvider);

  @override
  FoldersState build() {
    return FoldersState(folders: null, folderIndex: 0, isTerm: true);
  }

  void flip({bool? isTerm}) => state = state.copyWith(isTerm: isTerm ?? !state.isTerm);

  // Folders
  void setFolders(List<Folder> folders) => state = state.copyWith(folders: folders);

  void setFolderIndex(int index) => state = state.copyWith(folderIndex: index);

  Future<String?> addFolder(String title, String? parentId) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Folders.addFolder is called...");
      log.debug("addFolder input: title=$title, parentId=$parentId");

      final Map<String, dynamic> data = {"title": title};
      if (parentId != null) data["parentId"] = parentId;

      // Send request
      final result = await apiCall(() => _authDio.post("/api/treeNode/", data: data).notifyOnSuccess(l10n.folder_add_success));
      if (result.isFailure || result.dataOrNull == null) {
        log.warning("addFolder rejected: request failed or returned no data (isFailure=${result.isFailure})");
        NotificationService.showError(context: rootContext!, message: l10n.folder_add_failed);
        return null;
      }
      final newId = result.dataOrNull!["id"];
      log.debug("addFolder received new id=$newId");

      if (state.folders == null) {
        state.folders = List.from([Folder(id: newId, title: title)]);
      } else {
        state.folders!.add(Folder(id: newId, title: title));
        state = state.copyWith();
      }

      log.info("addFolder succeeded: id=$newId");
      return newId;
    } catch (e) {
      log.error("Folders.addFolder throws an error", e);
      NotificationService.showError(context: rootContext!, message: l10n.folder_add_failed);
      return null;
    } finally {
      log.info("Folders.addFolder call ended");
    }
  }

  /// Currently supports Folder.title field only
  Future<bool> setFolder(Folder folder) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Folders.setFolder is called...");
      log.debug("setFolder input: id=${folder.id}, title=${folder.title}");

      if (state.folders == null) {
        log.warning("setFolder rejected: no folders loaded in state");
        NotificationService.showError(message: l10n.folders_not_found);
        return false;
      }

      int? folderIndex;
      for (int i = 0; i < state.folders!.length; i++) {
        if (state.folders![i].id != folder.id) continue;
        folderIndex = i;
        break;
      }
      if (folderIndex == null) {
        log.warning("setFolder rejected: folder id=${folder.id} not found in state");
        NotificationService.showError(message: l10n.folder_not_found);
        return false;
      }
      log.debug("setFolder resolved folderIndex=$folderIndex");

      final Map<String, dynamic> data = {'_id': folder.id, 'title': folder.title};
      var result = await apiCall(() => _authDio.patch('/api/treeNode/', data: data).notifyOnSuccess(l10n.folder_set_success));
      if (result.isFailure) {
        log.warning("setFolder rejected: request failed for id=${folder.id}");
        NotificationService.showError(message: l10n.folder_set_failed);
        return false;
      }

      state.folders![folderIndex] = folder;
      state = state.copyWith();

      log.info("setFolder succeeded: id=${folder.id}, folderIndex=$folderIndex");
      return true;
    } catch (e) {
      log.error("Folders.setFolder throws an error", e);
      NotificationService.showError(message: l10n.folder_set_failed);
      return false;
    } finally {
      log.info("Folders.setFolder call ended");
    }
  }

  Future<bool> removeFolder(int index) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Folders.removeFolder is called...");
      log.debug("removeFolder input: index=$index");

      if (state.folders == null) {
        log.warning("removeFolder rejected: no folders loaded in state");
        NotificationService.showError(message: l10n.folders_not_found);
        return false;
      }
      if (index >= state.folders!.length || index < 0) {
        log.warning("removeFolder rejected: index=$index out of range (length=${state.folders!.length})");
        NotificationService.showError(message: l10n.folder_not_found);
        return false;
      }

      final targetId = state.folders![index].id;
      log.debug("removeFolder resolved id=$targetId for index=$index");

      final result = await apiCall(() => _authDio.delete('/api/treeNode/?treeNodeId=$targetId').notifyOnSuccess(l10n.folder_remove_success));
      if (result.isFailure) {
        log.warning("removeFolder rejected: request failed for id=$targetId");
        NotificationService.showError(message: l10n.folder_remove_failed);
        return false;
      }

      state.folders!.removeAt(index);
      state = state.copyWith();

      log.info("removeFolder succeeded: id=$targetId, index=$index");
      return true;
    } catch (e) {
      log.error("Folders.removeFolder throws an error", e);
      NotificationService.showError(message: l10n.folder_remove_failed);
      return false;
    } finally {
      log.info("Folders.removeFolder call ended");
    }
  }

  Future<bool> removeFolderById(String id) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Folders.removeFolderById is called...");
      log.debug("removeFolderById input: id=$id");

      if (state.folders == null) {
        log.warning("removeFolderById rejected: no folders loaded in state");
        NotificationService.showError(message: l10n.folders_not_found);
        return false;
      }

      int? folderIndex;
      for (int i = 0; i < state.folders!.length; i++) {
        if (state.folders![i].id != id) continue;
        folderIndex = i;
        break;
      }
      if (folderIndex == null) {
        log.warning("removeFolderById rejected: folder id=$id not found in state");
        NotificationService.showError(message: l10n.folder_not_found);
        return false;
      }
      log.debug("removeFolderById resolved folderIndex=$folderIndex");

      final result = await apiCall(() => _authDio.delete('/api/treeNode/?treeNodeId=$id').notifyOnSuccess(l10n.folder_remove_success));
      if (result.isFailure) {
        log.warning("removeFolderById rejected: request failed for id=$id");
        NotificationService.showError(message: l10n.folder_remove_failed);
        return false;
      }

      state.folders!.removeWhere((f) => f.id == id);
      state = state.copyWith();

      log.info("removeFolderById succeeded: id=$id");
      return true;
    } catch (e) {
      log.error("Folders.removeFolderById throws an error", e);
      NotificationService.showError(message: l10n.folder_remove_failed);
      return false;
    } finally {
      log.info("Folders.removeFolderById call ended");
    }
  }

  Future<bool> moveFolder(Folder folder, String? destId) async {
    AppLocalizations l10n = AppLocalizations.of(rootContext!)!;
    final log = talker;

    try {
      log.info("Folders.moveFolder is called...");
      log.debug("moveFolder input: id=${folder.id}, destId=$destId");

      final Map<String, dynamic> data = {"_id": folder.id};
      data["parentId"] = destId;

      // Send request
      final result = await apiCall(() => _authDio.patch("/api/treeNode/", data: {"treeNode": data}).notifyOnSuccess(l10n.folder_move_success));
      if (result.isFailure) {
        log.warning("moveFolder rejected: request failed for id=${folder.id}, destId=$destId");
        NotificationService.showError(context: rootContext!, message: l10n.folder_move_failed);
        return false;
      }

      log.info("moveFolder succeeded: id=${folder.id}, destId=$destId");
      return true;
    } catch (e) {
      log.error("Folders.moveFolder throws an error", e);
      NotificationService.showError(context: rootContext!, message: l10n.folder_move_failed);
      return false;
    } finally {
      log.info("Folders.moveFolder call ended");
    }
  }
}

final foldersProvider = NotifierProvider<Folders, FoldersState>(Folders.new);
