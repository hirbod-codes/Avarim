// Holds the current Plan (plan, name, etc.) as Riverpod state so any
// widget can `ref.watch(userInfoProvider)` and react when it changes —
// instead of every screen needing its own fetch/cache logic.
//
// - On first read, seeds itself from the on-disk cache (SubscriptionStorage)
//   so the UI has something to show instantly.
// - `refresh()` hits the server for the latest value, persists it to
//   SubscriptionStorage on success, and updates state for every watcher.
// - `info` is preserved across refresh/error so screens that just want
//   to *display* the user's info don't flicker to nothing while a
//   background refresh (e.g. the resume plan-check) is in flight.

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/subscription/models/subscription.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'subscription_storage.dart';

class SubscriptionState {
  final Subscription? subscription;
  final bool isLoading;
  final String? error;

  const SubscriptionState({this.subscription, this.isLoading = false, this.error});

  SubscriptionState copyWith({Subscription? subscription, bool clearInfo = false, bool? isLoading, String? error, bool clearError = false}) {
    return SubscriptionState(
      subscription: clearInfo ? null : (subscription ?? this.subscription),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SubscriptionNotifier extends Notifier<SubscriptionState> {
  @override
  SubscriptionState build() {
    // Fire-and-forget: seed state from disk cache as soon as it loads.
    _loadCached();
    return const SubscriptionState();
  }

  Future<void> _loadCached() async {
    final cached = await SubscriptionStorage.load();
    if (cached != null) {
      state = state.copyWith(subscription: cached);
    }
  }

  /// Hits the server for the user's subscription. Called by the
  /// resume-gate, but any widget could call this too (e.g. pull-to-refresh
  /// on a settings screen) — all watchers update together.
  Future<bool> refresh({bool silentError = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final subscription = await _fetchFromServer(silentError: silentError);
      await SubscriptionStorage.save(subscription);
      state = state.copyWith(subscription: subscription, isLoading: false, clearError: true);
      return true;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Failed to fetch your subscription.');
      return false;
    }
  }

  Future<Subscription?> _fetchFromServer({bool silentError = false}) async {
    final dio = ref.read(authDioProvider);
    final result = await apiCall<Subscription>(
      () => dio.get('/api/subscription', options: Options(extra: {GlobalErrorInterceptor.silentErrorsKey: silentError})),
      fromJson: (data) => Subscription.fromJson(data),
    );
    return result.dataOrNull;
  }

  /// Call on logout.
  Future<void> clear() async {
    await SubscriptionStorage.clear();
    state = const SubscriptionState();
  }
}

final subscriptionProvider = NotifierProvider<SubscriptionNotifier, SubscriptionState>(SubscriptionNotifier.new);
