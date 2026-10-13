import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'theme_mode';

Future<ThemeMode> loadThemeMode() async {
  final preferences = await SharedPreferences.getInstance();
  final name = preferences.getString(_key);
  return ThemeMode.values.firstWhere(
    (m) => m.name == name,
    orElse: () => ThemeMode.system, // first launch or unknown value
  );
}

Future<void> saveThemeMode(ThemeMode mode) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(_key, mode.name);
}
