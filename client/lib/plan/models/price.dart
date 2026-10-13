import 'package:avarim/plan/models/currency_label.dart';

/// Mirrors the backend's `priceSchema` — six currencies, each a
/// non-negative integer. The schema itself doesn't say what unit each
/// integer is in (whole units vs smallest subunit); see
/// CurrencyFormatter for the assumption this UI makes about that,
/// which you should confirm against your actual backend convention.
class Price {
  final double irr;
  final double usd;
  final double eur;
  final double btc;
  final double eth;

  const Price({required this.irr, required this.usd, required this.eur, required this.btc, required this.eth});

  factory Price.fromJson(Map<String, dynamic> json) =>
      Price(irr: json['IRR'] as double, usd: json['USD'] as double, eur: json['EUR'] as double, btc: json['BTC'] as double, eth: json['ETH'] as double);

  bool get isFree => irr == 0 && usd == 0 && eur == 0 && btc == 0 && eth == 0;

  double forCurrency(Currency currency) {
    switch (currency) {
      case Currency.usd:
        return usd;
      case Currency.eur:
        return eur;
      case Currency.irr:
        return irr;
      case Currency.btc:
        return btc;
      case Currency.eth:
        return eth;
    }
  }

  Map<String, dynamic> toJson() => {'IRR': irr, 'USD': usd, 'EUR': eur, 'BTC': btc, 'ETH': eth};

  double? operator [](String other) {
    if (Currency.usd.name == other) return usd;
    if (Currency.eur.name == other) return eur;
    if (Currency.irr.name == other) return irr;
    if (Currency.btc.name == other) return btc;
    if (Currency.eth.name == other) return eth;

    return null;
  }
}
