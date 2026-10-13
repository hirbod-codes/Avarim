import 'dart:convert';

import 'package:avarim/account/models/user_usage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserUsageStorage {
  static const _preferencesKey = 'userUsage';

  static Future<void> save(UserUsage? usage) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferencesKey, usage == null ? '' : jsonEncode(usage.toJson()));
  }

  static Future<UserUsage?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_preferencesKey);
    if (raw == null) return null;

    try {
      return UserUsage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // corrupted or outdated cache shape — treat as absent
    }
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_preferencesKey);
  }
}
