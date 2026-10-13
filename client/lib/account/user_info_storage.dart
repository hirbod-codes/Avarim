import 'dart:convert';

import 'package:avarim/account/models/user_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local cache of the last-fetched UserInfo. Two uses: lets the app
/// show something (name, plan, avatar key) instantly on next launch
/// before the network round-trip in _onAuthenticated() completes, and
/// gives other parts of the app a synchronous read instead of needing
/// to await userInfoProvider every time.
class UserInfoStorage {
  static const _preferencesKey = 'userInfo';

  static Future<void> save(UserInfo? info) async {
    if (info == null) {
      await clear();
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferencesKey, jsonEncode(info.toJson()));
  }

  static Future<UserInfo?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_preferencesKey);
    if (raw == null) return null;

    try {
      return UserInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // corrupted or outdated cache shape — treat as absent
    }
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_preferencesKey);
  }
}
