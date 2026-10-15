import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/localization/calendars/calendar_controller.dart';
import 'package:avarim/localization/components/calendar_switcher.dart';
import 'package:avarim/localization/components/locale_switcher.dart';
import 'package:avarim/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Shown once, before the auth page, on non-web platforms only —
/// go_router's redirect logic (see go_router.dart) routes here
/// whenever hasChosenLocaleAndCalendar() is false, and never again
/// once both are set.
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.welcome_to_avarim,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(l10n.message_choose_language, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 40),
              const Center(child: LocaleSwitcher()),
              const SizedBox(height: 16),
              const Center(child: CalendarSwitcher()),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: () async {
                  // Persist whatever's currently selected — even the
                  // device-derived default the pickers already show —
                  // so hasChosenLocaleAndCalendar() becomes true even
                  // if the user never touched either dropdown. Without
                  // this, tapping Continue without changing anything
                  // would loop back to onboarding forever.
                  final locale = ref.read(localeControllerProvider);
                  final calendar = ref.read(calendarControllerProvider);
                  await ref.read(localeControllerProvider.notifier).setLocale(locale);
                  await ref.read(calendarControllerProvider.notifier).setCalendarType(calendar);

                  if (context.mounted) context.go('/login');
                },
                child: Text(l10n.$continue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
