import 'dart:async';

import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/lib/talker.dart';

/// Generic loading/error wrapper for a single in-flight auth action
/// (login, signup, send-otp, verify-otp, reset-password — whichever
/// button was last pressed). One instance is reused across the whole
/// auth page rather than one per form, since only one action is ever
/// in flight at a time on this page.
///
/// This is deliberately separate from AuthState (lib/auth/auth_state.dart)
/// — that one tracks the app-wide session (logged in or not), this one
/// tracks whether *this specific button* is mid-request. They never need
/// to agree with each other; a signup-code-verify request can be loading
/// here while the global session is still `unauthenticated`.
class ActionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// Runs [action], exposing loading/error state via [state] so widgets
  /// can watch it (spinner on the button, error text below it) without
  /// each form needing its own try/catch/setState boilerplate.
  Future<void> run(Future<void> Function() action, {bool shouldNotifyUser = true}) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(action);
    state = result;
    talker.debug({state});

    final error = result.error;
    if (shouldNotifyUser && error != null && error is! DioException) {
      talker.error('caught error in action controller', error, result.stackTrace);

      NotificationService.showError(message: rootContext == null ? 'Something went wrong.' : AppLocalizations.of(rootContext!)!.uncaughtError);
    }
  }
}

final authActionControllerProvider = AsyncNotifierProvider.autoDispose<ActionController, void>(ActionController.new);

/// use case:
///
/// final provider = instantiateProvider();
///
/// await ref.read(provider.notifier).run(() => ref.read(authDioProvider).post('/api/user/preferences'));
///
/// final state = ref.read(provider);
AsyncNotifierProvider<ActionController, void> instantiateProvider() => AsyncNotifierProvider.autoDispose<ActionController, void>(ActionController.new);
