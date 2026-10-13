import 'calendar_date.dart';

enum CalendarType { gregorian, persian }

/// Converts between a Gregorian [DateTime] — the canonical internal
/// representation, matching whatever your backend stores/returns — and
/// a display-only [CalendarDate] in some other calendar system.
abstract class CalendarSystem {
  CalendarType get type;
  String get name;

  CalendarDate fromGregorian(DateTime date);
  DateTime toGregorian(CalendarDate date);
}
