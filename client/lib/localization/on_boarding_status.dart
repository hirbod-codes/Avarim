import 'package:avarim/localization/calendars/calendar_controller.dart';
import 'package:avarim/localization/locale_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Distinguishes "the user explicitly chose this" from "a device-derived
/// default was computed." LocaleController/CalendarController always
/// resolve to SOME value (saved, or a device-derived default) — these
/// checks look at whether the underlying SharedPreferences key was ever
/// actually written, which only happens via setLocale()/setCalendarType(),
/// never as a side effect of just computing a default.
Future<bool> hasChosenLocale() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.containsKey(LocaleController.preferencesKey);
}

Future<bool> hasChosenCalendar() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.containsKey(CalendarController.preferencesKey);
}

Future<bool> hasChosenLocaleAndCalendar() async {
  return (await hasChosenLocale()) && (await hasChosenCalendar());
}
