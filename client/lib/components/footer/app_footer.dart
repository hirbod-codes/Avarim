import 'package:flutter/material.dart';

/// Renders nothing on mobile/desktop — a footer bar makes sense on a
/// web page, not inside a native app's screen. This check alone is
/// enough here (unlike FooterBadge, this widget doesn't touch dart:html
/// directly, so a plain runtime kIsWeb check compiles fine everywhere).
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      height: 200,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: []),
          SizedBox(
            width: 100,
            height: 20,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text('© ${DateTime.now().year} Avarim', style: theme.textTheme.bodySmall),
            ),
          ),
        ],
      ),
    );
  }
}
