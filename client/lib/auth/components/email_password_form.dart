import 'package:avarim/auth/auth_controller.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/action_controller.dart';
import '../models/auth_models.dart';
import 'forgot_password_email_sheet.dart';
import 'otp_sheet.dart';

class EmailPasswordForm extends ConsumerStatefulWidget {
  final AuthMode mode;
  final ValueChanged<AuthMode> onModeChanged;
  final ValueChanged<AuthTokens>? onAuthenticated;

  const EmailPasswordForm({super.key, required this.mode, required this.onModeChanged, this.onAuthenticated});

  @override
  ConsumerState<EmailPasswordForm> createState() => _EmailPasswordFormState();
}

class _EmailPasswordFormState extends ConsumerState<EmailPasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool get _isSignUp => widget.mode == AuthMode.signUp;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _isSignUp ? await _submitSignUp() : await _submitLogin();
  }

  Future<void> _submitLogin() async {
    final api = ref.read(authControllerProvider.notifier);
    final controller = ref.read(authActionControllerProvider.notifier);
    AuthTokens? tokens;

    await controller.run(() async {
      tokens = await api.loginWithEmail(email: _emailController.text.trim(), password: _passwordController.text);
    });

    final state = ref.read(authActionControllerProvider);
    if (!state.hasError && tokens != null) {
      widget.onAuthenticated?.call(tokens!);
    }
  }

  Future<void> _submitSignUp() async {
    final email = _emailController.text.trim();
    final api = ref.read(authControllerProvider.notifier);
    final controller = ref.read(authActionControllerProvider.notifier);

    // Step 1: create the (unverified) account and trigger the code email.
    await controller.run(() => api.signUpWithEmail(email: email, password: _passwordController.text));
    final sendState = ref.read(authActionControllerProvider);
    if (sendState.hasError || !mounted) return;

    AppLocalizations l10n = AppLocalizations.of(context)!;
    // Step 2: same OTP sheet used for phone — the user must verify the
    // code before the account is usable, so we only continue once this
    // returns true with tokens in hand.
    AuthTokens? tokens;
    final verified = await showOtpSheet(
      context: context,
      destination: email,
      title: l10n.verify_your_email,
      onVerify: (code) async {
        tokens = await api.verifyEmailSignUp(email: email, code: code);
      },
      onResend: () => api.signUpWithEmail(email: email, password: _passwordController.text),
    );

    if (verified == true && tokens != null) {
      widget.onAuthenticated?.call(tokens!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(authActionControllerProvider);
    final isLoading = actionState.isLoading;

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _emailController,
            enabled: !isLoading,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(labelText: l10n.email, border: OutlineInputBorder()),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return l10n.email_required;
              if (!value.contains('@')) return l10n.enter_valid_email;
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            enabled: !isLoading,
            obscureText: true,
            autofillHints: [_isSignUp ? AutofillHints.newPassword : AutofillHints.password],
            decoration: InputDecoration(labelText: l10n.password, border: OutlineInputBorder()),
            validator: (value) {
              if (value == null || value.isEmpty) return l10n.password_required;
              if (_isSignUp && value.length < 8) return l10n.at_least_eight_characters;
              return null;
            },
          ),
          if (_isSignUp) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPasswordController,
              enabled: !isLoading,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.confirmPassword, border: OutlineInputBorder()),
              validator: (value) {
                if (value != _passwordController.text) return l10n.passwords_not_match;
                return null;
              },
            ),
          ],
          if (!_isSignUp) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: isLoading ? null : () => showForgotPasswordEmailSheet(context), child: Text(l10n.forgotPassword)),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: isLoading ? null : _submit,
            child: isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isSignUp ? l10n.signUp : l10n.login),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: isLoading ? null : () => widget.onModeChanged(_isSignUp ? AuthMode.login : AuthMode.signUp),
              child: Text(_isSignUp ? l10n.login_heading : l10n.signup_heading),
            ),
          ),
        ],
      ),
    );
  }
}
