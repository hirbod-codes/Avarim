import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_timezone/flutter_timezone.dart';

/// Device's actual IANA timezone (e.g. 'Asia/Tehran'). Requires the
/// flutter_timezone package — add to pubspec.yaml, I can't fetch
/// pub.dev from here to confirm the exact current API surface, this
/// matches the package's long-standing shape (a static
/// getLocalTimezone() call). Verify against whatever version you add.
///
/// Needed at all because Dart/Flutter core APIs only expose a raw UTC
/// offset (DateTime.timeZoneOffset), never an IANA zone name — and an
/// offset alone is ambiguous, since multiple zones share the same one
/// at any given moment.
///
/// Non-web for now, same as the country detection — flutter_timezone's
/// web support wasn't something I could verify here; test before
/// removing this gate if you want it there too.
Future<String?> deviceTimeZone() async {
  if (kIsWeb) return null;
  try {
    return (await FlutterTimezone.getLocalTimezone()).identifier;
  } catch (_) {
    return null;
  }
}
