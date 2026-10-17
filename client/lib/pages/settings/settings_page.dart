import 'dart:io';

import 'package:avarim/account/avatar/avatar_bytes_notifier.dart';
import 'package:avarim/account/models/user_info.dart';
import 'package:avarim/account/user_info_notifier.dart';
import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/api_call_extensions.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/auth/models/auth_models.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/localization/components/calendar_switcher.dart';
import 'package:avarim/localization/components/locale_switcher.dart';
import 'package:avarim/localization/components/timezone_switcher.dart';
import 'package:avarim/pages/settings/change_email_sheet.dart';
import 'package:avarim/pages/settings/change_password_sheet.dart';
import 'package:avarim/pages/settings/change_phone_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' hide context;

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(userInfoProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final userInfoState = ref.watch(userInfoProvider);
    // final subscriptionState = ref.watch(subscriptionProvider);
    // final allPlans = ref.watch(allPlansProvider);

    // if (userInfoState.isLoading || subscriptionState.isLoading || allPlans.isLoading) {
    //   return const Center(child: CircularProgressIndicator());
    // }

    if (userInfoState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (userInfoState.error != null || userInfoState.info == null) {
      return _RetryState(onRetry: () => ref.read(userInfoProvider.notifier).refresh());
    }

    // Plan? plan;
    // try {
    //   plan = allPlans.plans?.singleWhere((element) => element.title == subscriptionState.subscription?.planTitle);
    // } catch (_) {}

    return SettingsContent(userInfo: userInfoState.info!);
  }
}

class SettingsContent extends ConsumerStatefulWidget {
  final UserInfo userInfo;
  // final Subscription? subscription;
  // final Plan? plan;

  const SettingsContent({super.key, required this.userInfo});

  @override
  ConsumerState<SettingsContent> createState() => _SettingsContent();
}

class _SettingsContent extends ConsumerState<SettingsContent> {
  bool _isUploadingAvatar = false;
  bool _isRemovingAvatar = false;
  bool _isCancelingPlan = false;
  // bool _isAddingStorage = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmailAccount = widget.userInfo.authMethod == AuthMethod.email;

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // _SectionHeader(title: l10n.account),
          // _InfoTile(label: l10n.plan, value: widget.subscription?.planTitle ?? 'free'),
          // if (widget.userInfo.username != null) _InfoTile(label: l10n.username, value: widget.userInfo.username!),
          // if (widget.subscription != null)
          Button(
            type: ButtonType.outlined,
            label: l10n.remove_subscription,
            color: theme.colorScheme.error,
            isLoading: _isCancelingPlan,
            onPressed: () async {
              setState(() {
                _isCancelingPlan = true;
              });
              await apiCall(() => ref.read(authDioProvider).delete('/api/subscription').notifyOnSuccess(l10n.subscription_delete_success));
              setState(() {
                _isCancelingPlan = false;
              });
            },
          ),
          const SizedBox(height: 8),

          if (isEmailAccount) ...[
            _SectionHeader(title: l10n.email_password),
            _SettingsTile(
              icon: Icons.email_outlined,
              title: l10n.email,
              subtitle: widget.userInfo.email ?? '—',
              actionLabel: l10n.change,
              onTap: () => showChangeEmailSheet(context),
            ),
            _SettingsTile(
              icon: Icons.lock_outline,
              title: l10n.password,
              subtitle: '••••••••',
              actionLabel: l10n.change,
              onTap: () => showChangePasswordSheet(context),
            ),
          ] else ...[
            _SectionHeader(title: l10n.phoneNumber),
            _SettingsTile(
              icon: Icons.phone_outlined,
              title: l10n.phoneNumber,
              subtitle: widget.userInfo.phoneNumber ?? '—',
              actionLabel: l10n.change,
              onTap: () => showChangePhoneSheet(context),
            ),
          ],

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 10,
            children: [
              _SectionHeader(title: l10n.language),
              const LocaleSwitcher(),
            ],
          ),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 10,
            children: [
              _SectionHeader(title: l10n.calendar),
              const CalendarSwitcher(),
            ],
          ),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 10,
            children: [
              _SectionHeader(title: l10n.timeZone),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [Expanded(child: const TimezoneSwitcher())],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 10,
            children: [
              _SectionHeader(title: l10n.avatar),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: 10,
                children: [
                  Button(
                    type: ButtonType.outlined,
                    label: l10n.remove,
                    color: theme.colorScheme.error,
                    isLoading: _isRemovingAvatar,
                    onPressed: () async {
                      setState(() {
                        _isRemovingAvatar = true;
                      });
                      await apiCall(() => ref.read(authDioProvider).delete('/api/user/avatar').notifyOnSuccess(l10n.avatar_delete_success));
                      setState(() {
                        _isRemovingAvatar = false;
                      });
                    },
                  ),
                  Button(
                    type: ButtonType.outlined,
                    label: l10n.update,
                    isLoading: _isUploadingAvatar,
                    onPressed: () async {
                      setState(() {
                        _isUploadingAvatar = true;
                      });
                      await showDialog<String?>(context: context, builder: (_) => AvatarUpdateSetting());
                      setState(() {
                        _isUploadingAvatar = false;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),

          // if (widget.plan != null && widget.subscription != null && widget.subscription!.planTitle != 'free') ...[
          //   const SizedBox(height: 24),
          //   Row(
          //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //     crossAxisAlignment: CrossAxisAlignment.center,
          //     children: [
          //       _SectionHeader(title: l10n.storage_usage),
          //       Button(
          //         type: ButtonType.outlined,
          //         label: l10n.add_storage,
          //         isLoading: _isAddingStorage,
          //         onPressed: () async {
          //           setState(() {
          //             _isAddingStorage = true;
          //           });
          //           await showCheckoutDialog(context, plan: widget.plan!, subscription: widget.subscription!);
          //           setState(() {
          //             _isAddingStorage = false;
          //           });
          //         },
          //       ),
          //     ],
          //   ),
          //   const StorageUsage(),
          // ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  const _SettingsTile({required this.icon, required this.title, required this.subtitle, required this.actionLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: TextButton(onPressed: onTap, child: Text(actionLabel)),
    );
  }
}

class _RetryState extends StatelessWidget {
  final VoidCallback onRetry;

  const _RetryState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.account_load_failed, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.tryAgain)),
        ],
      ),
    );
  }
}

class AvatarUpdateSetting extends ConsumerStatefulWidget {
  const AvatarUpdateSetting({super.key});

  @override
  ConsumerState<AvatarUpdateSetting> createState() => _AvatarUpdateSettingState();
}

class _AvatarUpdateSettingState extends ConsumerState<AvatarUpdateSetting> {
  XFile? _image;
  Uint8List? _imageBytes;
  bool _loading = false;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();

    final XFile? picked = await picker.pickImage(source: source);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();

    setState(() {
      _image = picked;
      _imageBytes = bytes;
    });
  }

  bool isButtonDisabled() => _image == null || _image!.name.isEmpty || _imageBytes == null;

  Future<void> _upload() async {
    if (isButtonDisabled()) return;

    setState(() => _loading = true);

    try {
      AppLocalizations l10n = AppLocalizations.of(context)!;

      final length = await _image!.length();

      final authDio = ref.read(authDioProvider);

      final result = await apiCall(
        () => authDio
            .post(
              '/api/user/avatar/?fileName=${basename(_image!.name)}',
              data: _imageBytes!,
              options: Options(headers: {Headers.contentLengthHeader: length}),
            )
            .notifyOnSuccess(l10n.avatar_upload_success),
      );

      if (result.isSuccess) ref.read(avatarBytesProvider.notifier).save(_imageBytes!);

      if (!mounted) return;

      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.upload_image, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

              const SizedBox(height: 16),

              // Preview
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _image == null
                    ? Center(child: Text(l10n.no_image_selected))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: kIsWeb ? Image.network(_image!.path, fit: BoxFit.fitWidth) : Image.file(File(_image!.path), fit: BoxFit.fitWidth),
                      ),
              ),

              const SizedBox(height: 16),

              // Buttons: pick image
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo), label: Text(l10n.gallery)),

                  TextButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: Text(l10n.camera)),
                ],
              ),

              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: Text(l10n.cancel)),

                  const SizedBox(width: 8),

                  Button(
                    type: ButtonType.elevated,
                    color: theme.colorScheme.secondary,
                    onPressed: isButtonDisabled() ? null : _upload,
                    isLoading: _loading,
                    label: l10n.upload,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
