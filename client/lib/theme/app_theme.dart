import 'package:avarim/theme/app_colors.dart';
import 'package:flutter/material.dart';

const persianBlue = Color(0xFF1C39BB);
const persianLapis = Color(0xFF0F2A4A);
const persianTurquoise = Color(0xFF008695);
const persianGold = Color(0xFFC59B27);
const persianIvory = Color(0xFFF7F4EF);

final lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: persianBlue, dynamicSchemeVariant: DynamicSchemeVariant.fidelity).copyWith(
    primary: persianBlue,
    onPrimary: const Color(0xFFF0F2FF), // soft off-white
  ),
  extensions: const [
    AppColors(
      success: Color(0xFF2E7D32),
      onSuccess: Color(0xFFF1F8E9),
      warning: Color(0xFFF9A825), // amber
      onWarning: Color(0xFF2B1D00), // dark brown, softer than pure black
    ),
  ],
);

final darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: persianBlue, brightness: Brightness.dark),
  extensions: const [
    AppColors(
      success: Color(0xFF81C784),
      onSuccess: Color(0xFF003300),
      warning: Color(0xFFFFCA28), // lighter amber for dark backgrounds
      onWarning: Color(0xFF2B1D00),
    ),
  ],
);

final themeModeNotifier = ValueNotifier(ThemeMode.dark);
