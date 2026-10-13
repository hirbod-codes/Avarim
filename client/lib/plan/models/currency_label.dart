enum Currency {
  usd,
  eur,
  irr,
  btc,
  eth;

  static Currency toCurrency(String str) {
    switch (str) {
      case 'USD':
        return Currency.usd;
      case 'EUR':
        return Currency.eur;
      case 'IRR':
        return Currency.irr;
      case 'BTC':
        return Currency.btc;
      case 'ETH':
        return Currency.eth;
      default:
        throw Exception('Invalid currency provided');
    }
  }

  @override
  String toString() {
    switch (this) {
      case Currency.usd:
        return 'USD';
      case Currency.eur:
        return 'EUR';
      case Currency.irr:
        return 'IRR';
      case Currency.btc:
        return 'BTC';
      case Currency.eth:
        return 'ETH';
    }
  }
}

extension CurrencyLabel on Currency {
  String get label {
    switch (this) {
      case Currency.usd:
        return 'USD';
      case Currency.eur:
        return 'EUR';
      case Currency.irr:
        return 'Rial';
      case Currency.btc:
        return 'BTC';
      case Currency.eth:
        return 'ETH';
    }
  }
}
