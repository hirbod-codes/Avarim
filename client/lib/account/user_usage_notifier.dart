// Holds the current UserUsage (plan, name, etc.) as Riverpod state so any
// widget can `ref.watch(userInfoProvider)` and react when it changes —
// instead of every screen needing its own fetch/cache logic.
//
// - On first read, seeds itself from the on-disk cache (UserUsageStorage)
//   so the UI has something to show instantly.
// - `refresh()` hits the server for the latest value, persists it to
//   UserUsageStorage on success, and updates state for every watcher.
// - `info` is preserved across refresh/error so screens that just want
//   to *display* the user's info don't flicker to nothing while a
//   background refresh (e.g. the resume plan-check) is in flight.

import 'package:avarim/account/models/user_usage.dart';
import 'package:avarim/account/user_usage_storage.dart';
import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserUsageState {
  final UserUsage? usage;
  final bool isLoading;
  final String? error;

  const UserUsageState({this.usage, this.isLoading = false, this.error});

  UserUsageState copyWith({UserUsage? usage, bool clearInfo = false, bool? isLoading, String? error, bool clearError = false}) {
    return UserUsageState(
      usage: clearInfo ? null : (usage ?? this.usage),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class UserUsageNotifier extends Notifier<UserUsageState> {
  @override
  UserUsageState build() {
    // Fire-and-forget: seed state from disk cache as soon as it loads.
    _loadCached();
    return const UserUsageState();
  }

  Future<void> _loadCached() async {
    final cached = await UserUsageStorage.load();
    if (cached != null) {
      state = state.copyWith(usage: cached);
    }
  }

  /// Hits the server for the latest user usage info. Called by the
  /// resume-gate, but any widget could call this too (e.g. pull-to-refresh
  /// on a settings screen) — all watchers update together.
  Future<bool> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final usage = await _fetchFromServer();
      await UserUsageStorage.save(usage);
      state = state.copyWith(usage: usage, isLoading: false, clearError: true);
      return true;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Failed to your plan usage.');
      return false;
    }
  }

  Future<UserUsage?> _fetchFromServer() async {
    final authDio = ref.read(authDioProvider);
    final response = await apiCall<UserUsage?>(() => authDio.get('/api/user/usage'), fromJson: (data) => UserUsage.fromJson(data));
    return response.dataOrNull;
  }

  /// Call on logout.
  Future<void> clear() async {
    await UserUsageStorage.clear();
    state = const UserUsageState();
  }
}

final userUsageProvider = NotifierProvider<UserUsageNotifier, UserUsageState>(UserUsageNotifier.new);
