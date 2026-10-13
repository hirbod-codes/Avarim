// app_resume_plan_gate.dart
//
// Wraps your app (or a subtree) and, every time the app is *resumed*
// from the background (NOT on the initial cold-start launch), calls
// userInfoProvider's refresh() to re-check the user's plan, showing a
// blocking loading dialog while it does. On success the dialog
// auto-dismisses. On failure it shows an error + Retry button. Rapid
// resume events are debounced so we don't fire duplicate checks.
//
// Any other widget in your app can independently
// `ref.watch(userInfoProvider)` to read/react to the current UserInfo —
// it isn't tied to this dialog at all; this widget just triggers a
// refresh and reflects that one notifier's state while it runs.
//
// REQUIRES: flutter_riverpod, and your app wrapped in `ProviderScope`
// above this widget (runApp(ProviderScope(child: MyApp()))).

import 'dart:async';
import 'package:avarim/account/user_info_notifier.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wrap your app's root widget with this.
class AppResumePlanGate extends ConsumerStatefulWidget {
  final Widget child;

  /// Minimum gap between two triggered checks, to debounce rapid
  /// consecutive `resumed` events.
  final Duration debounceDuration;

  const AppResumePlanGate({super.key, required this.child, this.debounceDuration = const Duration(seconds: 2)});

  @override
  ConsumerState<AppResumePlanGate> createState() => _AppResumePlanGateState();
}

class _AppResumePlanGateState extends ConsumerState<AppResumePlanGate> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _dialogNavigatorKey = GlobalKey<NavigatorState>();

  // Guards against the very first `resumed` event, which fires as part
  // of the normal cold-start sequence and should NOT trigger a check.
  bool _hasLaunched = false;

  Timer? _debounceTimer;
  DateTime? _lastTriggeredAt;
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    if (!_hasLaunched) {
      _hasLaunched = true;
      return;
    }

    _debouncedTrigger();
  }

  void _debouncedTrigger() {
    final now = DateTime.now();
    if (_lastTriggeredAt != null && now.difference(_lastTriggeredAt!) < widget.debounceDuration) {
      return; // bounced — drop it
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      _lastTriggeredAt = DateTime.now();
      _showDialogAndRefresh();
    });
  }

  Future<void> _showDialogAndRefresh() async {
    if (_dialogShowing) return;
    final navState = _dialogNavigatorKey.currentState;
    if (navState == null) return;

    _dialogShowing = true;

    // Kick off the refresh; the dialog below watches userInfoProvider
    // and reacts to isLoading/error/success on its own.
    ref.read(userInfoProvider.notifier).refresh();

    await navState.push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        pageBuilder: (context, _, _) => _PlanCheckDialog(
          onDone: () {
            _dialogShowing = false;
            navState.maybePop();
          },
        ),
      ),
    );

    _dialogShowing = false;
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _dialogNavigatorKey,
      onGenerateRoute: (settings) => PageRouteBuilder(pageBuilder: (context, _, _) => widget.child),
    );
  }
}

/// Dialog content: spinner while userInfoProvider is loading, error +
/// retry on failure, auto-closes (via [onDone]) as soon as loading
/// finishes with no error.
class _PlanCheckDialog extends ConsumerWidget {
  final VoidCallback onDone;

  const _PlanCheckDialog({required this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(userInfoProvider);

    // React to state changes: close as soon as a refresh finishes
    // successfully. Scheduled post-frame so we don't call onDone (which
    // pops the dialog's route) during build.
    if (!state.isLoading && state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onDone());
    }

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
          child: state.error == null
              ? Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text(l10n.checking_plan)])
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 36),
                    const SizedBox(height: 12),
                    Text(state.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: () => ref.read(userInfoProvider.notifier).refresh(), child: Text(l10n.retry)),
                  ],
                ),
        ),
      ),
    );
  }
}
