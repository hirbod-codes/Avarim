import 'dart:convert';

import 'package:avarim/plan/models/plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local cache of the last-fetched Plan. Two uses: lets the app
/// show something (name, plan, avatar key) instantly on next launch
/// before the network round-trip in _onAuthenticated() completes, and
/// gives other parts of the app a synchronous read instead of needing
/// to await userInfoProvider every time.
class AllPlansStorage {
  static const _preferencesKey = 'allPlans';

  static Future<void> save(List<Plan>? plans) async {
    if (plans == null) {
      await clear();
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferencesKey, jsonEncode(plans.map((e) => e.toJson()).toList()));
  }

  static Future<List<Plan>?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_preferencesKey);
    if (raw == null) return null;

    try {
      return (jsonDecode(raw) as List<dynamic>).map((e) => Plan.fromJson(e)).toList();
    } catch (_) {
      return null; // corrupted or outdated cache shape — treat as absent
    }
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_preferencesKey);
  }
}
