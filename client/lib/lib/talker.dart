import 'package:flutter/foundation.dart';
import 'package:talker/talker.dart';

final talker = Talker(
  settings: TalkerSettings(enabled: true, useConsoleLogs: !kReleaseMode, useHistory: true, maxHistoryItems: 500),
  logger: TalkerLogger(
    settings: TalkerLoggerSettings(
      level: LogLevel.debug, // minimum level printed
      enableColors: true,
    ),
  ),
);
