import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/localization/timezone/timezone_controller.dart';
import 'package:avarim/localization/timezone/timezone_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TimezoneSwitcher extends ConsumerWidget {
  const TimezoneSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(timezoneControllerProvider);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return DropdownMenu<String>(
      initialSelection: current,
      enableFilter: true,
      requestFocusOnTap: true,
      label: Text(l10n.timeZone),
      onSelected: (zone) {
        if (zone != null) ref.read(timezoneControllerProvider.notifier).setZone(zone);
      },
      dropdownMenuEntries: [for (final zone in TimezoneService.allZoneNames) DropdownMenuEntry(value: zone, label: zone)],
    );
  }
}
