import 'package:avarim/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NavDestinationItem {
  final String path;
  final String Function(AppLocalizations l10n) label;
  final IconData icon;
  final IconData? selectedIcon;

  const NavDestinationItem({required this.path, required this.label, required this.icon, this.selectedIcon});
}

/// Add or remove entries here — NavBar and AppShell both adapt
/// automatically, nothing else needs touching. Material's
/// NavigationBar/NavigationRail both require at least 2 destinations,
/// so with fewer than that AppShell hides the nav entirely rather than
/// crash — this is exactly why it's been commented out until now: only
/// one route existed. Uncomment/add entries below once you have more.
List<NavDestinationItem> navDestinations = [
  // NavDestinationItem(path: '/app', label: 'App', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard),
  NavDestinationItem(path: '/app', label: (AppLocalizations l10n) => l10n.home, icon: Icons.home_outlined, selectedIcon: Icons.home),
  NavDestinationItem(path: '/pricing', label: (AppLocalizations l10n) => l10n.plan, icon: Icons.star_border, selectedIcon: Icons.star),
  NavDestinationItem(path: '/settings', label: (AppLocalizations l10n) => l10n.settings, icon: Icons.settings_outlined, selectedIcon: Icons.settings),
  if (kDebugMode) NavDestinationItem(path: '/test', label: (AppLocalizations l10n) => l10n.text, icon: Icons.abc_sharp, selectedIcon: Icons.abc_sharp),
];
