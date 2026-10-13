import 'package:avarim/account/account_controller.dart';
import 'package:avarim/api/action_controller.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showChangePasswordSheet(BuildContext context) {
  return showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const _ChangePasswordContent());
}

class _ChangePasswordContent extends ConsumerStatefulWidget {
  const _ChangePasswordContent();

  @override
  ConsumerState<_ChangePasswordContent> createState() => _ChangePasswordContentState();
}

class _ChangePasswordContentState extends ConsumerState<_ChangePasswordContent> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final account = ref.read(accountControllerProvider.notifier);
    final controller = ref.read(authActionControllerProvider.notifier);

    await controller.run(() => account.changePassword(currentPassword: _currentController.text, newPassword: _newController.text));

    final state = ref.read(authActionControllerProvider);
    if (!state.hasError && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(authActionControllerProvider);
    final isLoading = actionState.isLoading;

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.change_password_sheet, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _currentController,
              enabled: !isLoading,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: l10n.change_password_sheet_current_password, border: OutlineInputBorder()),
              validator: (v) => (v == null || v.isEmpty) ? l10n.required : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newController,
              enabled: !isLoading,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(labelText: l10n.change_password_sheet_new_password, border: OutlineInputBorder()),
              validator: (v) => (v == null || v.length < 8) ? l10n.at_least_eight_characters : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmController,
              enabled: !isLoading,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.change_password_sheet_confirm_new_password, border: OutlineInputBorder()),
              validator: (v) => v != _newController.text ? l10n.passwords_not_match : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isLoading ? null : _submit,
              child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.update_password),
            ),
          ],
        ),
      ),
    );
  }
}
