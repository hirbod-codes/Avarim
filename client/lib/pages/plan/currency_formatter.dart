import 'package:avarim/plan/models/currency_label.dart';
import 'package:intl/intl.dart';

/// Formats a raw integer price for display, using the digit set and
/// separators of [locale] — e.g. Persian digits/separators for 'fa',
/// comma-decimal/period-thousands for 'de'. Falls back to 'en' if
/// [locale] isn't a locale `intl` recognizes.
///
/// ASSUMPTION — confirm this against your actual backend before shipping:
/// the schema only guarantees a non-negative integer, it doesn't specify
/// the unit. This assumes the common convention of storing money in the
/// smallest subunit to avoid floating-point rounding bugs:
///   - USD/EUR stored in cents (divide by 100)
///   - IRR stored as whole Rial (Iran doesn't really use a fractional subunit in practice, so no division)
///   - BTC stored in satoshis (divide by 100,000,000)
///   - ETH stored in wei (divide by 10^18)
/// If your backend uses a different convention, this is the one place
/// to change it — nothing else in the UI knows or cares about units.
class CurrencyFormatter {
  static String format(double rawValue, Currency currency, {String locale = 'en'}) {
    locale = _resolveLocale(locale);

    switch (currency) {
      case Currency.usd:
        return '\$${_decimal((rawValue * 100).ceil(), 100, 2, locale)}';
      case Currency.eur:
        return '€${_decimal((rawValue * 100).ceil(), 100, 2, locale)}';
      case Currency.irr:
        return '${_thousands(rawValue.ceil(), locale)} Rial';
      case Currency.btc:
        return '${_trimmed((rawValue * 100000000).ceil(), 100000000, 8, locale)} BTC';
      case Currency.eth:
        return '${_trimmed((rawValue * 1000000000000000000).ceil(), 1000000000000000000, 8, locale)} ETH';
    }
  }

  /// Fixed-place decimal (no thousands grouping), matching the original
  /// `toStringAsFixed` behavior — just with locale-correct digits and
  /// decimal separator instead of a hardcoded '.'.
  static String _decimal(int raw, int divisor, int places, String locale) {
    final pattern = '0.${'0' * places}';
    return NumberFormat(pattern, locale).format(raw / divisor);
  }

  static String _thousands(int raw, String locale) {
    return NumberFormat.decimalPattern(locale).format(raw);
  }

  /// For crypto: show up to [maxDecimals] places but trim trailing
  /// zeros, so a whole-coin price doesn't render as "1.00000000 BTC".
  /// '#' means "digit, omit if zero", so building the pattern with
  /// [maxDecimals] of them lets NumberFormat do the trimming itself —
  /// using the locale's own decimal separator and digit set — instead
  /// of the previous string-surgery-after-the-fact approach.
  static String _trimmed(int raw, int divisor, int maxDecimals, String locale) {
    final pattern = '0.${'#' * maxDecimals}';
    return NumberFormat(pattern, locale).format(raw / divisor);
  }

  static String _resolveLocale(String locale) {
    return NumberFormat.localeExists(locale) ? locale : 'en';
  }
}

/// Human-readable byte formatting for `maxStorageBytes` (e.g. "5 GB"),
/// using [locale]'s digit set and decimal separator.
String formatBytes(int bytes, {String locale = 'en'}) {
  if (bytes <= 0) return '0 B';

  final resolvedLocale = NumberFormat.localeExists(locale) ? locale : 'en';

  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  final places = value == value.roundToDouble() ? 0 : 1;
  final formatted = NumberFormat('0.${'0' * places}', resolvedLocale).format(value);
  return '$formatted ${units[unitIndex]}';
}

/// Thousands-separated integer, for limits like "5,000 cards".
String formatCount(int value, {String locale = 'en'}) {
  if (!NumberFormat.localeExists(locale)) {
    locale = 'en';
  }

  return NumberFormat.decimalPattern(locale).format(value);
}
