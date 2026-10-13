import 'package:avarim/auth/auth_controller.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/action_controller.dart';
import '../models/auth_models.dart';
import 'otp_sheet.dart';

/// Passwordless phone auth: enter a number, get a code, verify it.
/// There's no separate login/signup mode here — the backend decides
/// whether the number is new (creates an account) or existing (logs in),
/// so the UI doesn't need a mode toggle the way the email form does.
class PhoneOtpForm extends ConsumerStatefulWidget {
  final ValueChanged<AuthTokens>? onAuthenticated;

  const PhoneOtpForm({super.key, this.onAuthenticated});

  @override
  ConsumerState<PhoneOtpForm> createState() => _PhoneOtpFormState();
}

class _PhoneOtpFormState extends ConsumerState<PhoneOtpForm> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phone = _phoneController.text.trim();
    final api = ref.read(authControllerProvider.notifier);
    final controller = ref.read(authActionControllerProvider.notifier);

    await controller.run(() => api.sendPhoneOtp(phone: phone));
    final sendState = ref.read(authActionControllerProvider);
    if (sendState.hasError || !mounted) return;

    AuthTokens? tokens;
    final verified = await showOtpSheet(
      context: context,
      destination: phone,
      title: 'Enter your code',
      onVerify: (code) async {
        tokens = await api.verifyPhoneOtp(phone: phone, code: code);
      },
      onResend: () => api.sendPhoneOtp(phone: phone),
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
          Text(l10n.phone_otp_form_heading, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            enabled: !isLoading,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: InputDecoration(labelText: l10n.phoneNumber, border: OutlineInputBorder()),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return l10n.change_phone_sheet_phone_number_required;
              return null;
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: isLoading ? null : _continue,
            child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.$continue),
          ),
        ],
      ),
    );
  }
}
