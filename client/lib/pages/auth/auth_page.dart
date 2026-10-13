import "package:avarim/auth/components/email_password_form.dart";
import "package:avarim/auth/components/phone_otp_form.dart";
import "package:avarim/auth/models/auth_models.dart";
import "package:avarim/l10n/app_localizations.dart";
import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "supported_auth_methods_provider.dart";

/// Top-level auth page. Toggles between email+password and passwordless
/// phone OTP — but only for whichever methods are actually available.
/// Two independent filters apply, in order:
///   1. supportedAuthMethodsProvider — what the backend currently supports.
///   2. Platform restriction — "currently phone only" on non-web is a
///      client-side product decision for this version of the app,
///      independent of whatever the backend reports. Remove the
///      `kIsWeb` filter below once other methods should be available
///      on mobile/desktop too.
/// One supported method skips the toggle entirely; zero shows a retry
/// state instead of a broken form.
class AuthPage extends ConsumerStatefulWidget {
  final ValueChanged<AuthTokens>? onAuthenticated;

  const AuthPage({super.key, this.onAuthenticated});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  AuthMethod? _method;
  AuthMode _mode = AuthMode.login;

  @override
  Widget build(BuildContext context) {
    final methodsAsync = ref.watch(supportedAuthMethodsProvider);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: methodsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              _RetryState(message: l10n.auth_page_checking_sign_in_methods_failed, onRetry: () => ref.invalidate(supportedAuthMethodsProvider)),
          data: (rawMethods) {
            final methods = kIsWeb ? rawMethods : rawMethods.where((m) => m == AuthMethod.phone).toList();

            if (methods.isEmpty) {
              return _RetryState(message: l10n.auth_page_sign_in_unavailable, onRetry: () => ref.invalidate(supportedAuthMethodsProvider));
            }

            if (_method == null || !methods.contains(_method)) {
              _method = methods.first;
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  Text(
                    _method == AuthMethod.email ? (_mode == AuthMode.signUp ? l10n.createYourAccount : l10n.welcomeBack) : l10n.logInOrSignUp,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (methods.length > 1) ...[
                    Center(
                      child: SegmentedButton<AuthMethod>(
                        segments: [
                          if (methods.contains(AuthMethod.email))
                            ButtonSegment(value: AuthMethod.email, label: Text(l10n.email), icon: Icon(Icons.email_outlined)),
                          if (methods.contains(AuthMethod.phone))
                            ButtonSegment(value: AuthMethod.phone, label: Text(l10n.phone), icon: Icon(Icons.sms_outlined)),
                        ],
                        selected: {_method!},
                        onSelectionChanged: (selection) => setState(() => _method = selection.first),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _method == AuthMethod.email
                        ? EmailPasswordForm(
                            key: const ValueKey("email"),
                            mode: _mode,
                            onModeChanged: (mode) => setState(() => _mode = mode),
                            onAuthenticated: widget.onAuthenticated,
                          )
                        : PhoneOtpForm(key: const ValueKey("phone"), onAuthenticated: widget.onAuthenticated),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RetryState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _RetryState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text(l10n.tryAgain)),
          ],
        ),
      ),
    );
  }
}
