import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/auth/auth_controller.dart';
import 'package:avarim/auth/auth_state.dart';
import 'package:avarim/localization/calendars/calendar_controller.dart';
import 'package:avarim/localization/device_defaults.dart';
import 'package:avarim/localization/timezone/timezone_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Add a language here + lib/l10n/app_<code>.arb — everything else
/// (switcher UI, persistence, RTL/LTR direction) adapts automatically.
const List<Locale> supportedLocales = [Locale('en'), Locale('fa'), Locale('de')];

const Map<String, String> localeDisplayNames = {'en': 'English', 'fa': 'فارسی', 'de': 'Deutsch'};

class LocaleController extends Notifier<Locale> {
  static const preferencesKey = 'locale';

  @override
  Locale build() {
    _restore();

    final (localeCode, _) = defaultLocaleAndCalendarForDevice();
    final matched = supportedLocales.where((l) => l.languageCode == localeCode);
    return matched.isNotEmpty ? matched.first : supportedLocales.first;
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(preferencesKey);
    if (saved == null) return;

    final match = supportedLocales.where((l) => l.languageCode == saved);
    if (match.isNotEmpty) state = match.first;
  }

  Future<void> setLocale(Locale? locale) async {
    locale ??= Locale('en');

    if (!supportedLocales.contains(locale)) return;

    if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
      final dio = ref.read(authDioProvider);
      final result = await apiCall(
        () => dio.post(
          '/api/user/preferences',
          data: {'language': locale!.languageCode, 'calendar': ref.read(calendarControllerProvider).name, 'timezone': ref.read(timezoneControllerProvider)},
        ),
      );
      if (result.isFailure) return;
    }

    state = locale;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(preferencesKey, locale.languageCode);
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);
