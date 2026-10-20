import 'dart:ui' show PlatformDispatcher;

import 'package:avarim/localization/calendars/calendar_system.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Country → (default language, default calendar), used ONLY for a
/// brand-new install with nothing saved yet and no account to sync
/// from. Extend this as you support more countries/languages —
/// anything not listed falls back to English + Gregorian.
const Map<String, (String locale, CalendarType calendar)> _countryDefaults = {
  'IR': ('fa', CalendarType.persian),
  'DE': ('de', CalendarType.gregorian),
  'AT': ('de', CalendarType.gregorian),
  'CH': ('de', CalendarType.gregorian),
  '_': ('en', CalendarType.gregorian),
};

/// Device's country from the OS locale setting — NOT IP/GPS geolocation.
/// Non-web only, per your explicit scoping: a browser's language
/// setting is already independently user-configurable and behaves
/// differently enough from an OS-level locale that folding it into the
/// same heuristic didn't seem right without you asking for it.
String? _deviceCountryCode() {
  if (kIsWeb) return null;
  return PlatformDispatcher.instance.locale.countryCode;
}

/// (locale, calendar) to use for a fresh install with nothing saved.
/// Falls back to English + Gregorian for any unlisted country, or web.
(String locale, CalendarType calendar) defaultLocaleAndCalendarForDevice() {
  final countryCode = _deviceCountryCode() ?? '_';
  final d = _countryDefaults['_'];
  return _countryDefaults.containsKey(countryCode) ? _countryDefaults[countryCode]! : d!;
}
