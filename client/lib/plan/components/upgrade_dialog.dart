import 'package:avarim/l10n/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

bool _upgradeDialogShowing = false;

/// Shows a blocking "Upgrade required" dialog with a generic message
/// (or your own [reason]), and an Upgrade button that navigates to
/// `/pricings`. Safe to call repeatedly — extra calls while one is
/// already open are ignored.
Future<void> showUpgradeDialog(BuildContext context, {String? reason}) async {
  if (_upgradeDialogShowing) return;
  _upgradeDialogShowing = true;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;

      return AlertDialog(
        icon: const Icon(Icons.workspace_premium_outlined, size: 32),
        title: Text(l10n.upgrade_required),
        content: Text(reason ?? l10n.limit_reached),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.notNow)),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              dialogContext.go("/pricing");
            },
            child: Text(l10n.upgrade),
          ),
        ],
      );
    },
  );

  _upgradeDialogShowing = false;
}
