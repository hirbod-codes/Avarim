import 'package:avarim/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocaleSwitcher extends ConsumerWidget {
  const LocaleSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeControllerProvider);

    return DropdownButton<Locale>(
      padding: EdgeInsets.all(4.0),
      value: current,
      onChanged: (locale) {
        if (locale != null) ref.read(localeControllerProvider.notifier).setLocale(locale);
      },
      items: [
        for (final locale in supportedLocales) DropdownMenuItem(value: locale, child: Text(localeDisplayNames[locale.languageCode] ?? locale.languageCode)),
      ],
    );
  }
}
