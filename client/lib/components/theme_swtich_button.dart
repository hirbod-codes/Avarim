import 'package:avarim/components/button.dart';
import 'package:avarim/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ThemeSwitchButton extends StatelessWidget {
  const ThemeSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Button(
      icon: themeModeNotifier.value == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
      color: theme.colorScheme.primary,
      type: ButtonType.text,
      onPressed: () {
        themeModeNotifier.value = themeModeNotifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      },
    );
  }
}
