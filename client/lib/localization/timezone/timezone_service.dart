import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Full IANA timezone database (~400 zones, every country) — no
/// curated subset to maintain. Call [initialize] once at app startup,
/// before any conversion is attempted.
class TimezoneService {
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  /// All IANA zone identifiers, e.g. 'Asia/Tehran', 'Europe/Berlin'.
  static List<String> get allZoneNames {
    final names = tz.timeZoneDatabase.locations.keys.toList();
    names.sort();
    return names;
  }

  static tz.Location location(String zoneName) => tz.getLocation(zoneName);

  /// Converts [date] (an instant — UTC, or a DateTime already carrying
  /// a meaningful offset) into the wall-clock time for [zoneName].
  static tz.TZDateTime convert(DateTime date, String zoneName) {
    return tz.TZDateTime.from(date, location(zoneName));
  }

  /// Wall-clock time in [zoneName] right now.
  static tz.TZDateTime now(String zoneName) => tz.TZDateTime.now(location(zoneName));
}
