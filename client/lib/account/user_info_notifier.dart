// Holds the current UserInfo (plan, name, etc.) as Riverpod state so any
// widget can `ref.watch(userInfoProvider)` and react when it changes —
// instead of every screen needing its own fetch/cache logic.
//
// - On first read, seeds itself from the on-disk cache (UserInfoStorage)
//   so the UI has something to show instantly.
// - `refresh()` hits the server for the latest value, persists it to
//   UserInfoStorage on success, and updates state for every watcher.
// - `info` is preserved across refresh/error so screens that just want
//   to *display* the user's info don't flicker to nothing while a
//   background refresh (e.g. the resume plan-check) is in flight.

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/account/models/user_info.dart';
import 'user_info_storage.dart';

class UserInfoState {
  final UserInfo? info;
  final bool isLoading;
  final String? error;

  const UserInfoState({this.info, this.isLoading = false, this.error});

  UserInfoState copyWith({UserInfo? info, bool clearInfo = false, bool? isLoading, String? error, bool clearError = false}) {
    return UserInfoState(
      info: clearInfo ? null : (info ?? this.info),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class UserInfoNotifier extends Notifier<UserInfoState> {
  @override
  UserInfoState build() {
    // Fire-and-forget: seed state from disk cache as soon as it loads.
    _loadCached();
    return const UserInfoState();
  }

  Future<void> _loadCached() async {
    final cached = await UserInfoStorage.load();
    if (cached != null) {
      state = state.copyWith(info: cached);
    }
  }

  /// Hits the server for the latest user/plan info. Called by the
  /// resume-gate, but any widget could call this too (e.g. pull-to-refresh
  /// on a settings screen) — all watchers update together.
  Future<bool> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final info = await _fetchFromServer();
      await UserInfoStorage.save(info);
      state = state.copyWith(info: info, isLoading: false, clearError: true);
      return true;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Failed to verify your plan.');
      return false;
    }
  }

  Future<UserInfo?> _fetchFromServer() async {
    final authDio = ref.read(authDioProvider);
    final response = await apiCall<UserInfo?>(() => authDio.get('/api/user/info'), fromJson: (data) => UserInfo.fromJson(data));
    return response.dataOrNull;
  }

  /// Call on logout.
  Future<void> clear() async {
    await UserInfoStorage.clear();
    state = const UserInfoState();
  }
}

final userInfoProvider = NotifierProvider<UserInfoNotifier, UserInfoState>(UserInfoNotifier.new);
