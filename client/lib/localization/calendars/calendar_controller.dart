import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/auth/auth_controller.dart';
import 'package:avarim/auth/auth_state.dart';
import 'package:avarim/localization/device_defaults.dart';
import 'package:avarim/localization/locale_controller.dart';
import 'package:avarim/localization/timezone/timezone_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_system.dart';
import 'gregorian_calendar.dart';
import 'persian_calendar.dart';

const Map<CalendarType, CalendarSystem> calendarSystems = {CalendarType.gregorian: GregorianCalendar(), CalendarType.persian: PersianCalendar()};

class CalendarController extends Notifier<CalendarType> {
  static const preferencesKey = 'calendarType';

  @override
  CalendarType build() {
    _restore();
    final (_, calendar) = defaultLocaleAndCalendarForDevice();
    return calendar;
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(preferencesKey);
    if (saved == null) return;

    final match = CalendarType.values.where((t) => t.name == saved);
    if (match.isNotEmpty) state = match.first;
  }

  Future<void> setCalendarType(CalendarType? type) async {
    type ??= CalendarType.gregorian;

    if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
      final dio = ref.read(authDioProvider);
      final result = await apiCall(
        () => dio.post(
          '/api/user/preferences',
          data: {'language': ref.read(localeControllerProvider).languageCode, 'calendar': type!.name, 'timezone': ref.read(timezoneControllerProvider)},
        ),
      );
      if (result.isFailure) return;
    }

    state = type;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(preferencesKey, type.name);
  }
}

final calendarControllerProvider = NotifierProvider<CalendarController, CalendarType>(CalendarController.new);

/// The currently-selected CalendarSystem instance, derived from
/// calendarControllerProvider — this is what UI code should actually
/// watch/use for conversions rather than looking up the map itself.
final activeCalendarProvider = Provider<CalendarSystem>((ref) {
  final type = ref.watch(calendarControllerProvider);
  return calendarSystems[type]!;
});
