import 'dart:convert';

import 'package:avarim/subscription/models/subscription.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:avarim/lib/talker.dart';

/// Local cache of the last-fetched Plan. Two uses: lets the app
/// show something (name, plan, avatar key) instantly on next launch
/// before the network round-trip in _onAuthenticated() completes, and
/// gives other parts of the app a synchronous read instead of needing
/// to await userInfoProvider every time.
class SubscriptionStorage {
  static const _preferencesKey = 'subscription';

  static Future<void> save(Subscription? subscription) async {
    if (subscription == null) {
      await clear();
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferencesKey, jsonEncode(subscription.toJson()));
  }

  static Future<Subscription?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_preferencesKey);
    if (raw == null) return null;

    try {
      return Subscription.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      talker.error('caught error in load method of SubscriptionStorage class', e);
      return null; // corrupted or outdated cache shape — treat as absent
    }
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_preferencesKey);
  }
}
