/// A date expressed in some non-Gregorian calendar system. Deliberately
/// just year/month/day + a display name — time-of-day always travels
/// alongside unchanged from the source Gregorian DateTime, since "hours
/// past midnight" doesn't meaningfully change across calendar systems
/// the way the date itself does.
class CalendarDate {
  final int year;
  final int month; // 1-based
  final int day; // 1-based
  final String monthName;

  const CalendarDate({required this.year, required this.month, required this.day, required this.monthName});

  @override
  String toString() => '$day $monthName $year';
}
