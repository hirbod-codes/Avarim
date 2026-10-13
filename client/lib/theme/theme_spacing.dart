class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class ResponsiveSpacing {
  final double padding;

  /// Space between distinct component groups/sections (e.g. between a
  /// header block and a list, or between two cards representing
  /// unrelated sections)
  final double groupSpacing;

  /// Space between individual components within the same group
  /// (e.g. a label and its input field, or two buttons in a row)
  final double componentSpacing;

  /// Space between items in a list (e.g. ListView.separated gap)
  final double listItemSpacing;

  const ResponsiveSpacing({required this.padding, required this.groupSpacing, required this.componentSpacing, required this.listItemSpacing});

  @override
  String toString() =>
      'padding: $padding, groupSpacing: $groupSpacing, '
      'componentSpacing: $componentSpacing, listItemSpacing: $listItemSpacing';
}

/// Returns proper padding and spacing values for a given parent container
/// width, following an 8pt grid across common breakpoints
/// (mobile / tablet / desktop / large desktop).
ResponsiveSpacing getSpacing(double width) {
  if (width < 360) {
    // Small phones
    return const ResponsiveSpacing(padding: 12, groupSpacing: 24, componentSpacing: 8, listItemSpacing: 4);
  } else if (width < 600) {
    // Standard phones
    return const ResponsiveSpacing(padding: 16, groupSpacing: 32, componentSpacing: 12, listItemSpacing: 8);
  } else if (width < 900) {
    // Small tablets / large phones landscape
    return const ResponsiveSpacing(padding: 24, groupSpacing: 40, componentSpacing: 16, listItemSpacing: 8);
  } else if (width < 1200) {
    // Tablets / small desktop
    return const ResponsiveSpacing(padding: 32, groupSpacing: 48, componentSpacing: 16, listItemSpacing: 12);
  } else if (width < 1600) {
    // Desktop
    return const ResponsiveSpacing(padding: 48, groupSpacing: 56, componentSpacing: 20, listItemSpacing: 12);
  } else {
    // Large / ultra-wide desktop
    return const ResponsiveSpacing(padding: 64, groupSpacing: 64, componentSpacing: 24, listItemSpacing: 16);
  }
}
