import 'package:avarim/auth/auth_controller.dart';
import 'package:avarim/api/action_controller.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'otp_code_input.dart';

enum _Step { enterEmail, enterCodeAndPassword }

/// Bottom sheet: enter email → receive a 6-digit code → enter code +
/// new password in one submit. Same two-step shape as email sign-up
/// and phone auth — every verification flow in this app works this way.
Future<void> showForgotPasswordEmailSheet(BuildContext context) {
  return showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const _ForgotPasswordEmailContent());
}

class _ForgotPasswordEmailContent extends ConsumerStatefulWidget {
  const _ForgotPasswordEmailContent();

  @override
  ConsumerState<_ForgotPasswordEmailContent> createState() => _ForgotPasswordEmailContentState();
}

class _ForgotPasswordEmailContentState extends ConsumerState<_ForgotPasswordEmailContent> {
  final _emailFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  final _otpKey = GlobalKey<OtpCodeInputState>();

  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _Step _step = _Step.enterEmail;
  String _code = '';

  @override
  void dispose() {
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!(_emailFormKey.currentState?.validate() ?? false)) return;

    final api = ref.read(authControllerProvider.notifier);
    final controller = ref.read(authActionControllerProvider.notifier);

    await controller.run(() => api.requestEmailPasswordReset(email: _emailController.text.trim()));

    final state = ref.read(authActionControllerProvider);
    if (!state.hasError && mounted) setState(() => _step = _Step.enterCodeAndPassword);
  }

  Future<void> _resend() async {
    final api = ref.read(authControllerProvider.notifier);
    final controller = ref.read(authActionControllerProvider.notifier);

    await controller.run(() => api.requestEmailPasswordReset(email: _emailController.text.trim()));
  }

  Future<void> _submit() async {
    if (_code.length != 6) return;
    if (!(_passwordFormKey.currentState?.validate() ?? false)) return;

    final api = ref.read(authControllerProvider.notifier);
    final controller = ref.read(authActionControllerProvider.notifier);

    await controller.run(() => api.completeEmailPasswordReset(email: _emailController.text.trim(), code: _code, newPassword: _newPasswordController.text));

    final state = ref.read(authActionControllerProvider);
    if (state.hasError) {
      _otpKey.currentState?.clear();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(authActionControllerProvider);
    final isLoading = actionState.isLoading;

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: _step == _Step.enterEmail
          ? Form(
              key: _emailFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Reset your password', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(l10n.forgot_password_email_sheet_heading, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    enabled: !isLoading,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return l10n.email_required;
                      if (!value.contains('@')) return l10n.enter_valid_email;
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: isLoading ? null : _sendCode,
                    child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.sendCode),
                  ),
                ],
              ),
            )
          : Form(
              key: _passwordFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.enter_code_new_password, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Code sent to ${_emailController.text.trim()}', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 20),
                  OtpCodeInput(key: _otpKey, enabled: !isLoading, onChanged: (value) => setState(() => _code = value)),
                  Center(
                    child: TextButton(onPressed: isLoading ? null : _resend, child: Text(l10n.sendCode)),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _newPasswordController,
                    enabled: !isLoading,
                    obscureText: true,
                    decoration: InputDecoration(labelText: l10n.new_password, border: OutlineInputBorder()),
                    validator: (value) {
                      if (value == null || value.length < 8) return l10n.at_least_eight_characters;
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    enabled: !isLoading,
                    obscureText: true,
                    decoration: InputDecoration(labelText: l10n.confirmPassword, border: OutlineInputBorder()),
                    validator: (value) {
                      if (value != _newPasswordController.text) return l10n.passwords_not_match;
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: isLoading || _code.length != 6 ? null : _submit,
                    child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.reset_password),
                  ),
                ],
              ),
            ),
    );
  }
}
