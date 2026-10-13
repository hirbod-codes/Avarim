import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/auth/auth_controller.dart';
import 'package:avarim/auth/auth_state.dart';
import 'package:avarim/localization/calendars/calendar_controller.dart';
import 'package:avarim/localization/locale_controller.dart';
import 'package:avarim/localization/timezone/device_timezone.dart';
import 'package:avarim/localization/timezone/timezone_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimezoneController extends Notifier<String> {
  static const _preferencesKey = 'timeZone';
  static const _fallbackZone = 'UTC';

  @override
  String build() {
    _restore();
    return _fallbackZone; // placeholder until the async check below resolves
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_preferencesKey);
    if (saved != null && TimezoneService.allZoneNames.contains(saved)) {
      state = saved;
      return;
    }

    final deviceZone = await deviceTimeZone();
    if (deviceZone != null && TimezoneService.allZoneNames.contains(deviceZone)) {
      state = deviceZone;
    } else {
      state = _fallbackZone;
    }
  }

  Future<void> setZone(String? zoneName) async {
    zoneName ??= _fallbackZone;

    if (!TimezoneService.allZoneNames.contains(zoneName)) return;

    if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
      final dio = ref.read(authDioProvider);
      final result = await apiCall(
        () => dio.post(
          '/api/user/preferences',
          data: {'language': ref.read(localeControllerProvider).languageCode, 'calendar': ref.read(calendarControllerProvider).name, 'timezone': zoneName},
        ),
      );
      if (result.isFailure) return;
    }

    state = zoneName;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferencesKey, zoneName);
  }
}

final timezoneControllerProvider = NotifierProvider<TimezoneController, String>(TimezoneController.new);
