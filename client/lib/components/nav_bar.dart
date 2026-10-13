import 'package:avarim/account/user_info_notifier.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'nav_destinations.dart';

/// Which physical form the nav takes at a given width. AppShell reads
/// this to decide where to place the widget (Scaffold.bottomNavigationBar
/// vs. beside the body in a Row) — NavigationBar and NavigationRail
/// attach to fundamentally different Scaffold slots, so the shell needs
/// to know which one it's dealing with, not just "render a nav".
enum NavBarPlacement { bottom, rail, extendedRail }

class NavBar extends ConsumerStatefulWidget {
  // Standard Material 3 adaptive breakpoints. Align these with your
  // theme_spacing.dart breakpoints if those differ — kept independent
  // here since I don't have that file's exact thresholds.
  static const railBreakpoint = 600.0;
  static const extendedRailBreakpoint = 1024.0;

  static NavBarPlacement placementFor(double width) {
    if (width < railBreakpoint) return NavBarPlacement.bottom;
    if (width < extendedRailBreakpoint) return NavBarPlacement.rail;
    return NavBarPlacement.extendedRail;
  }

  final NavBarPlacement placement;

  const NavBar({super.key, required this.placement});

  @override
  ConsumerState<NavBar> createState() => _NavBar();
}

class _NavBar extends ConsumerState<NavBar> {
  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = navDestinations.indexWhere((d) => d.path == location);
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex(context);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    final ui = ref.watch(userInfoProvider);

    if (ui.info?.role == 'admin' && navDestinations.indexWhere((e) => e.path == '/upload_audio') == -1) {
      navDestinations.add(
        NavDestinationItem(
          path: '/upload_audio',
          label: (AppLocalizations l10n) => 'Upload Audio',
          icon: Icons.upload_file_outlined,
          selectedIcon: Icons.upload_file_rounded,
        ),
      );
    }

    if (widget.placement == NavBarPlacement.bottom) {
      return NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => context.go(navDestinations[i].path),
        destinations: [
          for (final d in navDestinations) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon ?? d.icon), label: d.label(l10n)),
        ],
      );
    }

    final extended = widget.placement == NavBarPlacement.extendedRail;
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) => context.go(navDestinations[i].path),
      extended: extended,
      // extended rails show the label inline already — labelType must
      // be none in that case, or Flutter throws an assertion error.
      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.selected,
      destinations: [
        for (final d in navDestinations)
          NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon ?? d.icon), label: Text(d.label(l10n))),
      ],
    );
  }
}
