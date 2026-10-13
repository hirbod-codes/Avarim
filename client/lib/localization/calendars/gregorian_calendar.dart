import 'calendar_date.dart';
import 'calendar_system.dart';

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

class GregorianCalendar implements CalendarSystem {
  const GregorianCalendar();

  @override
  CalendarType get type => CalendarType.gregorian;

  @override
  String get name => 'Gregorian';

  @override
  CalendarDate fromGregorian(DateTime date) {
    return CalendarDate(year: date.year, month: date.month, day: date.day, monthName: _monthNames[date.month - 1]);
  }

  @override
  DateTime toGregorian(CalendarDate date) => DateTime(date.year, date.month, date.day);
}
