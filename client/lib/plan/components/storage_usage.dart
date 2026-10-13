import 'package:avarim/account/user_usage_notifier.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/subscription/subscription_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pure/presentational piece: pass in used + total bytes (e.g. total from
/// your subscription's `privileges.storageBytes`). No provider coupling.
class StorageUsageWidget extends ConsumerWidget {
  final int usedBytes;
  final int totalBytes;

  const StorageUsageWidget({super.key, required this.usedBytes, required this.totalBytes});

  double get _ratio {
    if (totalBytes <= 0) return 0;
    final r = usedBytes / totalBytes;
    return r.isNaN ? 0 : r.clamp(0.0, 1.0);
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final formatted = unitIndex == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$formatted ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final ratio = _ratio;
    final isNearLimit = ratio >= 0.9;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.storage, style: Theme.of(context).textTheme.titleSmall),
              Text(
                '${formatBytes(usedBytes)} / ${formatBytes(totalBytes)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: isNearLimit ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(isNearLimit ? theme.colorScheme.error : theme.colorScheme.primary),
            ),
          ),
          const SizedBox(height: 4),
          Text('${(ratio * 100).toStringAsFixed(1)}%', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Wrapper that fetches used bytes and combines it with a known total
/// (e.g. from the current subscription's privileges).
class StorageUsage extends ConsumerWidget {
  const StorageUsage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(subscriptionProvider);
    final userUsage = ref.watch(userUsageProvider);
    final l10n = AppLocalizations.of(context)!;

    if (subscription.isLoading || userUsage.isLoading) {
      return const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: LinearProgressIndicator(minHeight: 8));
    }

    if (subscription.error != null || userUsage.error != null || subscription.subscription == null || userUsage.usage == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(l10n.account_load_failed, style: Theme.of(context).textTheme.bodySmall)),
            Text(l10n.uncaughtError),
          ],
        ),
      );
    }

    return StorageUsageWidget(usedBytes: userUsage.usage!.storageBytes, totalBytes: subscription.subscription!.privileges.storageBytes);
  }
}
