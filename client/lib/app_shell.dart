import 'package:avarim/auth/auth_controller.dart';
import 'package:avarim/auth/auth_state.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/components/nav_bar.dart';
import 'package:avarim/components/nav_destinations.dart';
import 'package:avarim/components/topbar.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/localization/components/locale_switcher.dart';
import 'package:avarim/theme/app_theme.dart';
import 'package:avarim/theme/theme_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The main app chrome: TopBar always on top, NavBar adapting between
/// bottom placement (narrow) and a side rail (medium/wide), wrapping
/// whatever page content is passed in. Used for every authenticated
/// route — pages that shouldn't carry this chrome (a public landing
/// page, say) use a different shell entirely rather than this one with
/// flags to disable pieces of it. See public_shell.dart.
class AppShell extends ConsumerWidget {
  final Widget child;
  final Widget? title;

  const AppShell({super.key, required this.child, this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    bool unauthenticated = ref.read(authControllerProvider).status == AuthStatus.unauthenticated;
    if (unauthenticated) {
      AppLocalizations l10n = AppLocalizations.of(context)!;

      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(l10n.appTitle, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  const LocaleSwitcher(),
                  const SizedBox(width: 4),
                  Button(
                    icon: themeModeNotifier.value == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                    color: theme.colorScheme.onPrimary,
                    onColor: theme.colorScheme.primary,
                    type: ButtonType.text,
                    onPressed: () {
                      themeModeNotifier.value = themeModeNotifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                    },
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => context.go('/login'), child: Text(l10n.login)),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: () => context.go('/pricing'), child: Text(l10n.title_pricing)),
                  TextButton(onPressed: () => context.go('/about'), child: Text(l10n.title_about_us)),
                  TextButton(onPressed: () => context.go('/contact'), child: Text(l10n.title_contact_us)),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
    } else {
      return LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final spacing = getSpacing(maxWidth);

          final showNav = navDestinations.length >= 2;
          final placement = NavBar.placementFor(maxWidth);
          final navOnSide = showNav && placement != NavBarPlacement.bottom;
          final navOnBottom = showNav && placement == NavBarPlacement.bottom;

          final content = Container(width: double.infinity, height: double.infinity, padding: EdgeInsetsGeometry.all(spacing.padding), child: child);

          final body = navOnSide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NavBar(placement: placement),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                )
              : content;

          return Scaffold(
            backgroundColor: theme.colorScheme.surface,
            appBar: TopBar(title: title),
            body: body,
            // SingleChildScrollView(child: body),
            bottomNavigationBar: (navOnBottom ? const NavBar(placement: NavBarPlacement.bottom) : null),
          );
        },
      );
    }
  }
}
