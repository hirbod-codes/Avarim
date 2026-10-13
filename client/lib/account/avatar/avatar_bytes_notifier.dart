import 'dart:io';
import 'dart:typed_data';

import 'package:avarim/api/dio/dio_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:avarim/lib/talker.dart';

class AvatarBytesNotifier extends Notifier<Uint8List?> {
  static const _storageKey = 'avatar';
  static const _fileName = 'avatar_cache.jpg';

  @override
  Uint8List? build() {
    load();
    return null;
  }

  Future<void> load() async {
    // 1. Show cached bytes immediately (instant, no network).
    final cached = await readCached();
    if (cached != null) state = cached;

    // 2. Revalidate against the server in the background.
    await refresh(cachedAvatarKey: await getCachedAvatarKey());
  }

  Future<void> refresh({String? cachedAvatarKey}) async {
    try {
      final authDio = ref.read(authDioProvider);
      final response = await authDio.get('/api/user/avatar', options: Options(responseType: ResponseType.bytes));
      if (response.data == null) return;

      final bytes = Uint8List.fromList(response.data!);

      await save(bytes, avatarKey: cachedAvatarKey);
    } catch (e) {
      talker.error('caught error in fetchAvatar method of AccountController', e);
      return;
    }
  }

  /// Call after avatar deletion.
  Future<void> clear() async {
    state = null;
    final file = await _getCacheFile();
    if (file != null && await file.exists()) await file.delete();

    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }

  Future<File?> _getCacheFile() async {
    try {
      final dir = await getApplicationSupportDirectory(); // survives longer than cache dir
      return File('${dir.path}/$_fileName');
    } on MissingPlatformDirectoryException {
      talker.error('caught MissingPlatformDirectoryException exception in _getCacheFile method of AvatarCache class');
      return null;
    } catch (err) {
      talker.error('caught exception in _getCacheFile method of AvatarCache class', {err});
      return null;
    }
  }

  /// Returns cached bytes if a cache file exists, else null.
  Future<Uint8List?> readCached() async {
    final file = await _getCacheFile();
    if (file == null) return null;

    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } catch (_) {
      return null; // corrupted/partial file — treat as cache miss
    }
  }

  Future<String?> getCachedAvatarKey() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_storageKey);
  }

  Future<void> save(Uint8List bytes, {String? avatarKey}) async {
    state = bytes;

    final preferences = await SharedPreferences.getInstance();
    if (avatarKey != null) {
      await preferences.setString(_storageKey, avatarKey);
    } else {
      await preferences.remove(_storageKey);

      final file = await _getCacheFile();
      if (file == null) return;

      await file.writeAsBytes(bytes, flush: true);
    }
  }
}

final avatarBytesProvider = NotifierProvider<AvatarBytesNotifier, Uint8List?>(AvatarBytesNotifier.new);
