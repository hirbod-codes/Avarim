import 'package:shamsi_date/shamsi_date.dart';

import 'calendar_date.dart';
import 'calendar_system.dart';

/// Wraps the shamsi_date package (add to pubspec.yaml: shamsi_date: ^latest).
/// I can't fetch pub.dev from here to confirm the exact current API
/// surface — this matches the well-established, long-standing shape of
/// that package (Jalali/Gregorian classes, .toJalali()/.toGregorian()
/// conversions, .formatter.mN for the localized month name). Double
/// check against whatever version you actually add.
class PersianCalendar implements CalendarSystem {
  const PersianCalendar();

  @override
  CalendarType get type => CalendarType.persian;

  @override
  String get name => 'Persian';

  @override
  CalendarDate fromGregorian(DateTime date) {
    final jalali = Gregorian.fromDateTime(date).toJalali();
    return CalendarDate(year: jalali.year, month: jalali.month, day: jalali.day, monthName: jalali.formatter.mN);
  }

  @override
  DateTime toGregorian(CalendarDate date) {
    final jalali = Jalali(date.year, date.month, date.day);
    return jalali.toGregorian().toDateTime();
  }
}
